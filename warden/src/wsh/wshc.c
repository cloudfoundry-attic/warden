#define _GNU_SOURCE

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "pump.h"
#include "un.h"

int loop(int fd) {
  char buf[1024];
  size_t buflen = sizeof(buf);
  int fds[4];
  size_t fdslen = 4;
  int rv;
  int i;

  rv = un_recv_fds(fd, buf, buflen, fds, fdslen);
  if (rv < 0) {
    perror("recv_fds");
    exit(1);
  }

  pump_t p;

  pump_pair_t pp[3];
  pump_pair_init(&pp[0], &p, STDIN_FILENO, fds[0]);
  pump_pair_init(&pp[1], &p, fds[1], STDOUT_FILENO);
  pump_pair_init(&pp[2], &p, fds[2], STDERR_FILENO);

  for (;;) {
    pump_init(&p);

    for (i = 0; i < 3; i++) {
      pump_add_pair(&p, &pp[i]);
    }

    if (fds[3] >= 0) {
      pump_add_fd(&p, fds[3], PUMP_READ | PUMP_EXCEPT);
    }

    rv = pump_select(&p);
    if (rv == -1) {
      perror("select");
      exit(1);
    }

    for (i = 0; i < 3; i++) {
      pump_pair_splice(&pp[i]);
    }

    if (pump_ready(&p, fds[3], PUMP_READ | PUMP_EXCEPT)) {
      int status;

      rv = read(fds[3], &status, sizeof(status));
      if (rv < sizeof(status)) {
        /* Error, or short read. */
        exit(255);
      }

      /* One more splice to make sure kernel buffers are emptied */
      for (i = 0; i < 3; i++) {
        pump_pair_splice(&pp[i]);
      }

      exit(status);
    }
  }

  return 0;
}

int main(int argc, char **argv) {
  int fd;

  if (argc < 2) {
    fprintf(stderr, "Usage: %s SOCKET\n", argv[0]);
    exit(1);
  }

  fd = un_connect(argv[1]);
  if (fd < 0) {
    perror("connect");
    exit(1);
  }

  return loop(fd);
}
