#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "barrier.h"
#include "status_reader.h"
#include "status_writer.h"
#include "test_util.h"
#include "util.h"

typedef struct {
  uint8_t got_status;
  int status;
  barrier_t *barrier;
  char       domain_path[256];
  pthread_t  thread;
  status_reader_t reader;
} sink_t;

static sink_t *sink_alloc(const char *domain_path) {
  sink_t *s = NULL;

  s = calloc(1, sizeof(*s));
  assert(NULL != s);

  strcpy(s->domain_path, domain_path);
  s->barrier = barrier_alloc();

  return s;
}

static void sink_free(sink_t *s) {
  assert(NULL != s);

  barrier_free(s->barrier);
  free(s);
}

static void *run_status_writer(void *data) {
  assert(NULL != data);

  status_writer_run((status_writer_t *) data);

  return NULL;
}

static void *run_sink(void *data) {
  sink_t  *s     = NULL;
  int      fd    = -1;
  uint8_t  hup   = 0;
  int      ii    = 0;

  assert(NULL != data);

  s = (sink_t *) data;

  for (ii = 0; ii < 5 && fd == -1; ii++) {
    fd = unix_domain_connect(s->domain_path);
    usleep(100000);
  }
  barrier_lift(s->barrier);

  if (-1 == fd) {
    perror("connect()");
    return NULL;
  }

  status_reader_init(&(s->reader), fd);
  status_reader_run(&(s->reader), &hup);
  if (!hup) {
    s->got_status = 1;
    s->status = s->reader.status;
  }

  close(fd);

  return NULL;
}

void test_status_writer(void) {
  char             domain_path[256];
  int              listen_sock = 0;
  int              fd          = 0;
  status_writer_t *sw          = NULL;
  pthread_t        sw_thread;
  sink_t          *sinks[3];
  int              ii          = 0;
  int              status      = 10;

  signal(SIGPIPE, SIG_IGN);

  strcpy(domain_path, "/tmp/muxer_test_sock_XXXXXX");
  fd = mkstemp(domain_path);
  assert(-1 != fd);
  close(fd);

  for (ii = 0; ii < 3; ++ii) {
    sinks[ii] = sink_alloc(domain_path);
  }

  listen_sock = create_unix_domain_listener(domain_path, 10);
  assert(-1 != listen_sock);

  sw = status_writer_alloc(listen_sock, NULL);

  if (pthread_create(&sw_thread, NULL, run_status_writer, sw)) {
    perror("pthread_create");
    assert(0);
  }

  /* Create sinks and wait for them to connect */
  for (ii = 0; ii < 3; ++ii) {
    if (pthread_create(&(sinks[ii]->thread), NULL, run_sink, sinks[ii])) {
      perror("pthread_create");
      assert(0);
    }
    barrier_wait(sinks[ii]->barrier);
  }

  status_writer_finish(sw, status);

  pthread_join(sw_thread, NULL);
  for (ii = 0; ii < 3; ++ii) {
    pthread_join(sinks[ii]->thread, NULL);
    TEST_CHECK(sinks[ii]->got_status == 1);
    TEST_CHECK(sinks[ii]->status == status);
  }

  /* Cleanup */
  status_writer_free(sw);
  for (ii = 0; ii < 3; ++ii) {
    sink_free(sinks[ii]);
  }
  unlink(domain_path);
}
