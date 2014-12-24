#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/queue.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "barrier.h"
#include "dlog.h"
#include "muxer.h"
#include "ring_buffer.h"
#include "util.h"

#define READ_BUF_SIZE 4096

typedef enum {
  STATE_CREATED,
  STATE_STARTED,
  STATE_STOPPED,
} muxer_state_t;

typedef struct muxer_sink_s muxer_sink_t;

struct muxer_sink_s {
  int fd;

  LIST_ENTRY(muxer_sink_s) next_sink;
};

LIST_HEAD(muxer_sink_head, muxer_sink_s);

struct muxer_s {
  muxer_state_t          state;
  ring_buffer_t          *buf;        /* buffer data is read into */

  int                     source_fd;  /* where data is read from */
  uint32_t                source_pos; /* number of bytes read from the source */
  struct muxer_sink_head  sinks;      /* where data is written to */

  barrier_t               *client_barrier; /* lifted once a client has connected */
  pthread_mutex_t         lock;

  int                     accept_fd;  /* where new connections are created */
  pthread_t               accept_thread;
  int                     acceptor_stop_pipe[2];

  int                     rw_stop_pipe[2];
};

static muxer_sink_t *muxer_sink_alloc(int sink_fd) {
  muxer_sink_t *sink = NULL;

  assert(sink_fd >= 0);

  sink = calloc(1, sizeof(*sink));
  assert(NULL != sink);

  sink->fd = sink_fd;

  return sink;
}

static void muxer_sink_free(muxer_sink_t *sink) {
  assert(NULL != sink);

  close(sink->fd);
  free(sink);
}

static void muxer_free_sinks(muxer_t *muxer) {
  muxer_sink_t *cur = NULL;
  muxer_sink_t *prev = NULL;

  assert(NULL != muxer);

  cur = LIST_FIRST(&(muxer->sinks));

  while (NULL != cur) {
    prev = cur;
    cur = LIST_NEXT(cur, next_sink);
    LIST_REMOVE(prev, next_sink);
    muxer_sink_free(prev);
  }
}

/**
 * Writes the contents of the ring buffer to the sink.
 *
 * NB: The lock must be held when calling this function.
 */
static int muxer_catchup_sink(const muxer_t *muxer, int sink_fd) {
  uint32_t  pos      = 0;
  size_t    buf_size = 0;
  uint8_t   hup      = 0;
  uint8_t  *buf      = NULL;

  assert(NULL != muxer);
  assert(sink_fd >= 0);

  DLOG("catching sink up, fd=%d", sink_fd);

  buf_size = ring_buffer_size(muxer->buf);
  pos = muxer->source_pos - buf_size;
  pos = htonl(pos);

  atomic_write(sink_fd, &pos, sizeof(uint32_t), &hup);
  if (hup) {
    DLOG("hup on fd=%d", sink_fd);

    /* Sink closed conn */
    return -1;
  }

  buf = ring_buffer_dup(muxer->buf);
  atomic_write(sink_fd, buf, buf_size, NULL);

  free(buf);

  return hup;
}

static void muxer_write_to_sinks(muxer_t *muxer, uint8_t *data, size_t count) {
  muxer_sink_t *cur = NULL;
  muxer_sink_t *prev = NULL;
  ssize_t nwritten = 0;
  uint8_t hup = 0;

  assert(NULL != muxer);
  assert(NULL != data);

  DLOG("writing %zu bytes to all sinks", count);

  cur = LIST_FIRST(&(muxer->sinks));

  while (NULL != cur) {
    nwritten = atomic_write(cur->fd, data, count, &hup);

    DLOG("wrote nbytes=%zu to fd=%d", nwritten, cur->fd);

    if (hup) {
      /* Other side closed conn */
      DLOG("hup on fd=%d", cur->fd);

      prev = cur;
      cur = LIST_NEXT(cur, next_sink);
      LIST_REMOVE(prev, next_sink);
      muxer_sink_free(prev);
    } else {
      cur = LIST_NEXT(cur, next_sink);
    }
  }

  DLOG("done writing to sinks");
}

/**
 * Reads as many bytes as available from the source and writes the data to the
 * sinks.
 */
static uint8_t muxer_pump(muxer_t *muxer, uint8_t stopped) {
  uint8_t read_buf[READ_BUF_SIZE];
  ssize_t nread = 0;
  uint8_t hup = 0;

  nread = atomic_read(muxer->source_fd, read_buf, READ_BUF_SIZE, &hup);

  DLOG("read nbytes=%zu from fd=%d", nread, muxer->source_fd);

  checked_lock(&(muxer->lock));

  ring_buffer_append(muxer->buf, read_buf, nread);
  muxer->source_pos += nread;

  muxer_write_to_sinks(muxer, read_buf, nread);

  checked_unlock(&(muxer->lock));

  return hup;
}

/**
 * Accepts incoming connections, creates sinks for them, and writes the current
 * ring buffer state.
 */
void *muxer_acceptor(void *data) {
  muxer_t      *muxer    = NULL;
  uint8_t       events   = 0;
  int           sink_fd  = -1;
  muxer_sink_t *sink     = NULL;

  assert(NULL != data);

  muxer = (muxer_t *) data;

  DLOG("accepting connections on fd=%d", muxer->accept_fd);

  while (1) {
    events = wait_readable_or_stop(muxer->accept_fd, muxer->acceptor_stop_pipe[0]);

    if (events & MUXER_READABLE) {
      sink_fd = accept(muxer->accept_fd, NULL, NULL);
      if (-1 == sink_fd) {
        perror("accept()");
        break;
      }

      set_cloexec(sink_fd);

      DLOG("accepted connection on fd=%d, client_fd=%d\n",
           muxer->accept_fd,
           sink_fd);

      /* Prevent the reader/writer thread from reading any new data */
      checked_lock(&(muxer->lock));

      if (-1 == muxer_catchup_sink(muxer, sink_fd)) {
        /* Other side closed conn */
        checked_unlock(&(muxer->lock));
        continue;
      }

      sink = muxer_sink_alloc(sink_fd);
      LIST_INSERT_HEAD(&(muxer->sinks), sink, next_sink);

      checked_unlock(&(muxer->lock));

      /* Allow anyone waiting for a client to continue */
      barrier_lift(muxer->client_barrier);
    }

    if (events & MUXER_STOP) {
      DLOG("received stop for accept_fd=%d", muxer->accept_fd);
      break;
    }
  }

  close(muxer->accept_fd);

  return NULL;
}

muxer_t *muxer_alloc(int accept_fd, int source_fd, size_t ring_buf_size) {
  muxer_t *muxer = NULL;
  int err = 0, ii = 0;

  assert(accept_fd >= 0);
  assert(source_fd >= 0);
  assert(ring_buf_size > 0);

  muxer = calloc(1, sizeof(*muxer));
  assert(NULL != muxer);

  muxer->state = STATE_CREATED;

  muxer->accept_fd = accept_fd;
  set_nonblocking(muxer->accept_fd);
  set_cloexec(muxer->accept_fd);

  muxer->source_fd = source_fd;
  set_nonblocking(muxer->source_fd);
  muxer->source_pos = 0;

  muxer->buf = ring_buffer_alloc(ring_buf_size);
  err = pthread_mutex_init(&(muxer->lock), NULL);
  assert(!err);

  LIST_INIT(&(muxer->sinks));

  if (-1 == pipe(muxer->acceptor_stop_pipe)) {
    perror("pipe()");
    assert(0);
  }
  for (ii = 0; ii < 2; ++ii) {
    set_cloexec(muxer->acceptor_stop_pipe[ii]);
  }

  if (-1 == pipe(muxer->rw_stop_pipe)) {
    perror("pipe()");
    assert(0);
  }
  for (ii = 0; ii < 2; ++ii) {
    set_cloexec(muxer->rw_stop_pipe[ii]);
  }

  muxer->client_barrier = barrier_alloc();

  return muxer;
}

void muxer_run(muxer_t *muxer) {
  muxer_sink_t *sink   = NULL;
  uint8_t       hup    = 0;
  uint8_t       events = 0;

  assert(NULL != muxer);

  DLOG("running muxer for accept_fd=%d source_fd=%d",
        muxer->accept_fd, muxer->source_fd);

  checked_lock(&(muxer->lock));

  assert(STATE_CREATED == muxer->state);
  muxer->state = STATE_STARTED;

  checked_unlock(&(muxer->lock));

  if (pthread_create(&muxer->accept_thread, NULL, muxer_acceptor, muxer)) {
    perror("pthread_create");
    assert(0);
  }

  while (1) {
    events = wait_readable_or_stop(muxer->source_fd, muxer->rw_stop_pipe[0]);

    if (events & MUXER_READABLE) {
      DLOG("data ready on source_fd=%d", muxer->source_fd);

      hup = muxer_pump(muxer, (events & MUXER_STOP));

      if (hup) {
        break;
      }
    }

    if (events & MUXER_STOP) {
      DLOG("received stop event for source_fd=%d", muxer->source_fd);
      break;
    }
  }

  close(muxer->source_fd);

  /* Stop acceptor thread */
  atomic_write(muxer->acceptor_stop_pipe[1], "x", 1, &hup);
  pthread_join(muxer->accept_thread, NULL);

  /* Close sinks */
  LIST_FOREACH(sink, &(muxer->sinks), next_sink) {
    close(sink->fd);
  }

  DLOG("muxer done, accept_fd=%d, source_fd=%d",
       muxer->accept_fd, muxer->source_fd);
}

void muxer_wait_for_client(muxer_t *muxer) {
  assert(NULL != muxer);

  barrier_wait(muxer->client_barrier);
}

void muxer_stop(muxer_t *muxer) {
  uint8_t hup = 0;

  assert(NULL != muxer);

  DLOG("stopping muxer, accept_fd=%d source_fd=%d",
       muxer->accept_fd, muxer->source_fd);

  checked_lock(&(muxer->lock));

  assert(STATE_STARTED == muxer->state);
  muxer->state = STATE_STOPPED;

  checked_unlock(&(muxer->lock));

  /* Notify thread executing muxer_run() */
  atomic_write(muxer->rw_stop_pipe[1], "x", 1, &hup);
}

void muxer_free(muxer_t *muxer) {
  int ii = 0;

  assert(NULL != muxer);

  ring_buffer_free(muxer->buf);
  muxer->buf = NULL;

  pthread_mutex_destroy(&(muxer->lock));

  for (ii = 0; ii < 2; ++ii) {
    close(muxer->acceptor_stop_pipe[ii]);
    close(muxer->rw_stop_pipe[ii]);
  }

  muxer_free_sinks(muxer);

  barrier_free(muxer->client_barrier);

  free(muxer);
}
