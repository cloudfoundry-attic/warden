#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>

#include "barrier.h"
#include "util.h"

struct barrier_s {
  pthread_mutex_t lock;
  pthread_cond_t  cv;
  uint8_t         lifted;
};

barrier_t *barrier_alloc(void) {
  barrier_t *barrier = NULL;
  int err = 0;

  barrier = malloc(sizeof(*barrier));
  assert(NULL != barrier);

  barrier->lifted = 0;

  err = pthread_mutex_init(&(barrier->lock), NULL);
  assert(!err);

  err = pthread_cond_init(&(barrier->cv), NULL);
  assert(!err);

  return barrier;
}

void barrier_lift(barrier_t *barrier) {
  assert(NULL != barrier);

  checked_lock(&(barrier->lock));

  barrier->lifted = 1;
  pthread_cond_broadcast(&(barrier->cv));

  checked_unlock(&(barrier->lock));
}

void barrier_wait(barrier_t *barrier) {
  assert(NULL != barrier);

  checked_lock(&(barrier->lock));

  if (!barrier->lifted) {
    pthread_cond_wait(&(barrier->cv), &(barrier->lock));
  }

  checked_unlock(&(barrier->lock));
}

void barrier_free(barrier_t *barrier) {
  assert(NULL != barrier);

  pthread_mutex_destroy(&(barrier->lock));
  pthread_cond_destroy(&(barrier->cv));

  free(barrier);
}
