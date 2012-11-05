#ifndef PUMP_H
#define PUMP_H 1

#define PUMP_READ   1
#define PUMP_WRITE  2
#define PUMP_EXCEPT 4

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
int pump_add_fd(pump_t *p, int fd, int mode);
int pump_add_pair(pump_t *p, pump_pair_t *pp);
int pump_ready(pump_t *p, int fd, int mode);
int pump_select(pump_t *p);

void pump_pair_init(pump_pair_t *pp, pump_t *p, int rfd, int wfd);
int pump_pair_splice(pump_pair_t *pp);
int pump_pair_copy(pump_pair_t *pp);

#endif
