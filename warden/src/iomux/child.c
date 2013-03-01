#include <assert.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

#include "child.h"
#include "util.h"

child_t *child_create(char **argv, size_t argv_size) {
  child_t *child = NULL;
  pid_t cpid;
  int ii = 0;
  char buf;
  uint8_t hup = 0;

  signal(SIGPIPE, SIG_IGN);

  assert(NULL != argv);
  assert(argv_size > 0);

  child = calloc(1, sizeof(*child));
  assert(NULL != child);

  child->argv = calloc(argv_size + 1, sizeof(char *));
  assert(NULL != child->argv);

  child->argv_size = argv_size;

  for (ii = 0; ii < argv_size; ++ii) {
    child->argv[ii] = strdup(argv[ii]);
    assert(NULL != child->argv[ii]);
  }

  if (-1 == pipe(child->stdout)) {
    perror("pipe()");
    assert(0);
  }

  if (-1 == pipe(child->stderr)) {
    perror("pipe()");
    assert(0);
  }

  if (-1 == pipe(child->barrier)) {
    perror("pipe()");
    assert(0);
  }
  for (ii = 0; ii < 2; ++ii) {
    set_cloexec(child->barrier[ii]);
  }

  cpid = fork();
  if (-1 == cpid) {
    perror("fork()");
    assert(0);
  }

  if (0 == cpid) {
    dup2(child->stdout[1], STDOUT_FILENO);
    dup2(child->stderr[1], STDERR_FILENO);

    for (ii = 0; ii < 2; ++ii) {
      close(child->stdout[ii]);
      close(child->stderr[ii]);
    }

    /* This child should die with its parent */
    prctl(PR_SET_PDEATHSIG, SIGKILL, 0, 0, 0);

    /* In child, wait to be unblocked */
    atomic_read(child->barrier[0], &buf, 1, &hup);

    if (hup) {
      exit(1);
    }

    execvp(argv[0], argv);

    /* NOTREACHED */
    exit(0);
  }

  child->pid = cpid;

  close(child->stdout[1]);
  close(child->stderr[1]);

  return child;
}

void child_continue(child_t *child) {
  assert(NULL != child);

  atomic_write(child->barrier[1], "X", 1, NULL);
}

void child_free(child_t *child) {
  int ii = 0;

  assert(NULL != child);

  for (ii = 0; ii < 2; ++ii) {
    close(child->stdout[ii]);
    close(child->stderr[ii]);
    close(child->barrier[ii]);
  }

  for (ii = 0; ii < child->argv_size; ++ii) {
    free(child->argv[ii]);
  }
  free(child->argv);

  free(child);
}
