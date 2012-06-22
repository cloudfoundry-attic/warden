#include <arpa/inet.h>
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "barrier.h"
#include "muxer.h"
#include "test_util.h"
#include "util.h"

typedef struct {
  uint8_t   *data;
  size_t     capacity;
  size_t     size;
  size_t     target; /* How many bytes should be read before lifting barrier */
  barrier_t *barrier;
  char       domain_path[256];
  pthread_t  thread;
} sink_t;

static sink_t *sink_alloc(const char *domain_path, size_t target, size_t cap) {
  sink_t *s = NULL;

  s = calloc(1, sizeof(*s));
  assert(NULL != s);

  s->data = calloc(cap, 1);
  assert(NULL != s->data);

  s->capacity = cap;
  s->target = target;

  strcpy(s->domain_path, domain_path);
  s->barrier = barrier_alloc();

  return s;
}

static void sink_free(sink_t *s) {
  assert(NULL != s);

  barrier_free(s->barrier);
  free(s->data);
  free(s);
}

static void *run_muxer(void *data) {
  assert(NULL != data);

  muxer_run((muxer_t *) data);

  return NULL;
}

static void *run_sink(void *data) {
  sink_t  *s     = NULL;
  int      fd    = -1;
  uint8_t  hup   = 0;
  ssize_t  nread = 0;
  int      ii    = 0;

  assert(NULL != data);

  s = (sink_t *) data;

  for (ii = 0; ii < 5 && fd == -1; ii++) {
    fd = unix_domain_connect(s->domain_path);
    usleep(100000);
  }
  if (-1 == fd) {
    perror("connect()");
    barrier_lift(s->barrier);
    return NULL;
  }

  do {
    nread = atomic_read(fd, s->data + s->size, 1, &hup);
    s->size += nread;

    if (s->size >= s->target) {
      barrier_lift(s->barrier);
    }
  } while (!hup);

  return NULL;
}

void test_muxer(void) {
  int        ring_buffer_size = 256;
  int        source[2];
  char       domain_path[256];
  int        listen_sock      = 0;
  int        fd               = 0;
  muxer_t   *muxer            = NULL;
  pthread_t  muxer_thread;
  sink_t    *sinks[3];
  int        ii               = 0;
  uint8_t    hup              = 0;
  uint32_t  *pos              = 0;

  signal(SIGPIPE, SIG_IGN);

  if (-1 == pipe(source)) {
    perror("pipe");
    assert(0);
  }

  strcpy(domain_path, "/tmp/muxer_test_sock_XXXXXX");
  fd = mkstemp(domain_path);
  assert(-1 != fd);
  close(fd);

  sinks[0] = sink_alloc(domain_path, ring_buffer_size, 3 * ring_buffer_size);
  sinks[1] = sink_alloc(domain_path, 2 * ring_buffer_size, 3 * ring_buffer_size);
  sinks[2] = sink_alloc(domain_path, ring_buffer_size, 3 * ring_buffer_size);

  listen_sock = create_unix_domain_listener(domain_path, 10);
  assert(-1 != listen_sock);

  muxer = muxer_alloc(listen_sock, source[0], ring_buffer_size);

  if (pthread_create(&muxer_thread, NULL, run_muxer, muxer)) {
    perror("pthread_create");
    assert(0);
  }

  /* Fill the ring buffer */
  for (ii = 0; ii < ring_buffer_size; ++ii) {
    atomic_write(source[1], "A", 1, &hup);
  }

  /* Create the first two sinks */
  for (ii = 0; ii < 2; ++ii) {
    if (pthread_create(&(sinks[ii]->thread), NULL, run_sink, sinks[ii])) {
      perror("pthread_create");
      assert(0);
    }
  }

  /* Wait for the data to make it into the ring buffer */
  barrier_wait(sinks[0]->barrier);

  /* Write enough data to wrap the ring buffer */
  for (ii = 0; ii < ring_buffer_size; ++ii) {
    atomic_write(source[1], "B", 1, &hup);
  }

  /* Wait for the data to make it into the ring buffer */
  barrier_wait(sinks[1]->barrier);

  /* Create the third sink and wait until it's caught up */
  if (pthread_create(&(sinks[2]->thread), NULL, run_sink, sinks[2])) {
    perror("pthread_create");
    assert(0);
  }
  barrier_wait(sinks[2]->barrier);

  /* All done, wait for everyone to finish */
  muxer_stop(muxer);
  pthread_join(muxer_thread, NULL);
  for (ii = 0; ii < 3; ++ii) {
    pthread_join(sinks[ii]->thread, NULL);
  }

  /* Sinks 0 and 1 should receive the same data */
  TEST_CHECK(sinks[0]->size == 516);
  pos = (uint32_t *) sinks[0]->data;
  TEST_CHECK(*pos == 0);

  TEST_CHECK(sinks[1]->size == 516);
  pos = (uint32_t *) sinks[1]->data;
  TEST_CHECK(*pos == 0);

  TEST_CHECK(!memcmp(sinks[0]->data, sinks[1]->data, sinks[0]->size));

  /* Sink 2 missed the first ring buffer's worth of data */
  TEST_CHECK(sinks[2]->size == 260);
  pos = (uint32_t *) sinks[2]->data;
  TEST_CHECK(ntohl(*pos) == 256);


  /* Cleanup */
  muxer_free(muxer);
  for (ii = 0; ii < 3; ++ii) {
    sink_free(sinks[ii]);
  }
  unlink(domain_path);
}
