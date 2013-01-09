#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/select.h>
#include <unistd.h>

#include "pump.h"
#include "util.h"

void pump_init(pump_t *p) {
  p->nfd = 0;

  FD_ZERO(&p->rfds);
  FD_ZERO(&p->wfds);
  FD_ZERO(&p->efds);
}

void pump_pair_init(pump_pair_t *pp, pump_t *p, int rfd, int wfd) {
  pp->p = p;
  pp->rfd = rfd;
  pp->wfd = wfd;

  /* Both sides may refer to the same file description if they refer to a PTY,
   * so configuring them differently may not have the desired effects.
   * Therefore, simply configure both sides to be blocking. */
  fcntl_set_nonblock(rfd, 0);
  fcntl_set_nonblock(wfd, 0);
}

void pump_pair_close(pump_pair_t *pp) {
  close(pp->rfd);
  pp->rfd = -1;
  close(pp->wfd);
  pp->wfd = -1;
}

int pump_add_fd(pump_t *p, int fd, int mode) {
  if (fd < 0) {
    return 0;
  }

  if (fd > p->nfd) {
    p->nfd = fd;
  }

  if (mode & PUMP_READ) {
    FD_SET(fd, &p->rfds);
  }

  if (mode & PUMP_WRITE) {
    FD_SET(fd, &p->wfds);
  }

  if (mode & PUMP_EXCEPT) {
    FD_SET(fd, &p->efds);
  }

  return 1;
}

int pump_add_pair(pump_t *p, pump_pair_t *pp) {
  int j = 0;

  j += pump_add_fd(p, pp->rfd, PUMP_READ | PUMP_EXCEPT);
  j += pump_add_fd(p, pp->wfd, PUMP_WRITE | PUMP_EXCEPT);

  return j;
}

int pump_ready(pump_t *p, int fd, int mode) {
  int rv = 0;

  if (mode & PUMP_READ) {
    rv |= FD_ISSET(fd, &p->rfds);
  }

  if (mode & PUMP_WRITE) {
    rv |= FD_ISSET(fd, &p->wfds);
  }

  if (mode & PUMP_EXCEPT) {
    rv |= FD_ISSET(fd, &p->efds);
  }

  return rv;
}

int pump_select(pump_t *p) {
  return select(FD_SETSIZE, &p->rfds, NULL, &p->efds, NULL);
}

int pump_pair_splice(pump_pair_t *pp) {
  int rv;

  if (!FD_ISSET(pp->rfd, &pp->p->rfds)) {
    return 0;
  }

  if (!FD_ISSET(pp->wfd, &pp->p->wfds)) {
    return 0;
  }

  rv = splice(pp->rfd, NULL, pp->wfd, NULL, 64 * 1024, SPLICE_F_NONBLOCK);
  if (rv == -1) {
    perror("splice");
    exit(1);
  } else if (rv == 0) {
    pump_pair_close(pp);
  }

  return rv;
}

int pump_pair_copy(pump_pair_t *pp) {
  char buf[64 * 1024];
  char *ptr = buf;
  int nr, nw;

  if (!FD_ISSET(pp->rfd, &pp->p->rfds)) {
    return 0;
  }

  do {
    nr = read(pp->rfd, buf, sizeof(buf));
  } while (nr == -1 && errno == EINTR);

  if (nr <= 0) {
    pump_pair_close(pp);
    return nr;
  }

  while (nr) {
    do {
      nw = write(pp->wfd, ptr, nr);
    } while (nw == -1 && errno == EINTR);

    if (nw <= 0) {
      pump_pair_close(pp);
      return nw;
    }

    ptr += nw;
    nr -= nw;
  }

  return 0;
}
