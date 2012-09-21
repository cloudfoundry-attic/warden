#define _GNU_SOURCE

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

  fcntl_mix_nonblock(rfd);
  fcntl_mix_nonblock(wfd);
}

void pump_pair_close(pump_pair_t *pp) {
  close(pp->rfd);
  pp->rfd = -1;
  close(pp->wfd);
  pp->wfd = -1;
}

int pump_add(pump_t *p, pump_pair_t *pp) {
  if (pp->rfd < 0 || pp->wfd < 0) {
    return 0;
  }

  if (pp->rfd > p->nfd) {
    p->nfd = pp->rfd;
  }

  if (pp->wfd > p->nfd) {
    p->nfd = pp->wfd;
  }

  FD_SET(pp->rfd, &p->rfds);
  FD_SET(pp->wfd, &p->wfds);

  FD_SET(pp->rfd, &p->efds);
  FD_SET(pp->wfd, &p->efds);

  return 1;
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
