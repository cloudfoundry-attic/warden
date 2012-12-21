#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "util.h"

void fcntl_set_cloexec(int fd, int on) {
  int rv;
  int fl;

  rv = fcntl(fd, F_GETFD);
  if (rv == -1) {
    perror("fcntl");
    abort();
  }

  fl = rv;
  if (on) {
    fl |= FD_CLOEXEC;
  } else {
    fl &= ~FD_CLOEXEC;
  }

  rv = fcntl(fd, F_SETFD, fl);
  if (rv == -1) {
    perror("fcntl");
    abort();
  }
}

void fcntl_set_nonblock(int fd, int on) {
  int rv;
  int fl;

  rv = fcntl(fd, F_GETFL);
  if (rv == -1) {
    perror("fcntl");
    abort();
  }

  fl = rv;
  if (on) {
    fl |= O_NONBLOCK;
  } else {
    fl &= ~O_NONBLOCK;
  }

  rv = fcntl(fd, F_SETFL, fl);
  if (rv == -1) {
    perror("fcntl");
    abort();
  }
}

int run(const char *p1, const char *p2) {
  char path[MAXPATHLEN];
  int rv;
  char *argv[2];
  int status;

  rv = snprintf(path, sizeof(path), "%s/%s", p1, p2);
  assert(rv < sizeof(path));

  argv[0] = path;
  argv[1] = NULL;

  rv = fork();
  if (rv == -1) {
    perror("fork");
    abort();
  }

  if (rv == 0) {
    execvp(argv[0], argv);
    perror("execvp");
    abort();
  } else {
    rv = waitpid(rv, &status, 0);
    if (rv == -1) {
      perror("waitpid");
      abort();
    }

    if (WEXITSTATUS(status) != 0) {
      fprintf(stderr, "Process for \"%s\" exited with %d\n", path, WEXITSTATUS(status));
      return -1;
    }
  }

  return 0;
}

void setproctitle(char **argv, const char *title) {
  char *last;
  int i;
  size_t len;
  char *p;
  size_t n;

  last = argv[0];
  i = 0;

  while (last == argv[i]) {
    last += strlen(argv[i++]) + 1;
  }

  len = last - argv[0];
  p = argv[0];
  n = strlen(title);
  assert(len > n);

  /* Assign argv termination sentinel */
  argv[1] = NULL;

  /* Copy title */
  strncpy(p, title, n);
  len -= n;
  p += n;

  /* Set remaining bytes to \0 */
  memset(p, '\0', len);
}
