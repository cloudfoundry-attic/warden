#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "barrier.h"
#include "util.h"

int barrier_open(barrier_t *bar) {
  int rv;
  int aux[2] = { -1, -1 };

  rv = pipe(aux);
  if (rv == -1) {
    perror("pipe");
    goto err;
  }

  bar->fd[0] = aux[0];
  bar->fd[1] = aux[1];
  return 0;

err:
  if (aux[0] >= 0) close(aux[0]);
  if (aux[1] >= 0) close(aux[1]);
  return -1;
}

void barrier_close(barrier_t *bar) {
  close(bar->fd[0]);
  close(bar->fd[1]);
}

void barrier_mix_cloexec(barrier_t *bar) {
  fcntl_mix_cloexec(bar->fd[0]);
  fcntl_mix_cloexec(bar->fd[1]);
}

void barrier_close_wait(barrier_t *bar) {
  close(bar->fd[0]);
  bar->fd[0] = -1;
}

void barrier_close_signal(barrier_t *bar) {
  close(bar->fd[1]);
  bar->fd[1] = -1;
}

int barrier_wait(barrier_t *bar) {
  int nread;
  char buf[1];

  barrier_close_signal(bar);

  nread = read(bar->fd[0], buf, sizeof(buf));

  barrier_close_wait(bar);

  if (nread == -1) {
    perror("read");
    return -1;
  } else if (nread == 0) {
    return -1;
  }

  return 0;
}

int barrier_signal(barrier_t *bar) {
  int nwritten;
  char byte = '\0';

  barrier_close_wait(bar);

  nwritten = write(bar->fd[1], &byte, 1);

  barrier_close_signal(bar);

  if (nwritten == -1) {
    perror("write");
    return -1;
  }

  return 0;
}
