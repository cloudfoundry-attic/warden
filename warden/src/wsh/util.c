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

void fcntl_mix(int fd, int flag) {
  int rv;

  rv = fcntl(fd, F_GETFD);
  if (rv == -1) {
    perror("fcntl");
    abort();
  }

  rv = fcntl(fd, F_SETFD, rv | flag);
  if (rv == -1) {
    perror("fcntl");
    abort();
  }
}

void fcntl_mix_cloexec(int fd) {
  fcntl_mix(fd, O_CLOEXEC);
}

void fcntl_mix_nonblock(int fd) {
  fcntl_mix(fd, O_NONBLOCK);
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
