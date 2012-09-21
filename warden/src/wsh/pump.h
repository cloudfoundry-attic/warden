#ifndef PUMP_H
#define PUMP_H 1

typedef struct pump_s pump_t;

struct pump_s {
  int nfd;

  fd_set rfds;
  fd_set wfds;
  fd_set efds;
};

typedef struct pump_pair_s pump_pair_t;

struct pump_pair_s {
  pump_t *p;

  int rfd;
  int wfd;
};

void pump_init(pump_t *p);
int pump_add(pump_t *p, pump_pair_t *pp);
int pump_select(pump_t *p);

void pump_pair_init(pump_pair_t *pp, pump_t *p, int rfd, int wfd);
int pump_pair_splice(pump_pair_t *pp);

#endif
