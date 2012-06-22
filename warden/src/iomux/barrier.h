#ifndef BARRIER_H
#define BARRIER_H 1

typedef struct barrier_s barrier_t;

barrier_t *barrier_alloc(void);

void barrier_lift(barrier_t *barrier);

void barrier_wait(barrier_t *barrier);

void barrier_free(barrier_t *barrier);

#endif
