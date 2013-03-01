#include <assert.h>
#include <linux/limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "child.h"
#include "dlog.h"
#include "muxer.h"
#include "status_writer.h"
#include "util.h"

static void *run_muxer(void *data) {
  assert(NULL != data);

  muxer_run((muxer_t *) data);

  return NULL;
}

static void *run_status_writer(void *data) {
  assert(NULL != data);

  status_writer_run((status_writer_t *) data);

  return NULL;
}

int main(int argc, char *argv[]) {
  int              backlog          = 10;
  muxer_t         *muxers[2]        = {NULL, NULL};
  status_writer_t *sw               = NULL;
  child_t         *child            = NULL;
  int              child_status     = -1;
  int              ring_buffer_size = 65535;
  int              fds[3]           = {-1, -1, -1};
  int              ii               = 0, exit_status = 0, nwritten = 0;
  pthread_t        sw_thread, muxer_threads[2];
  char             socket_paths[3][PATH_MAX + 1];
  char             *socket_names[3] = { "stdout.sock", "stderr.sock", "status.sock" };
  barrier_t        *barrier = NULL;

  if (argc < 3) {
    fprintf(stderr, "Usage: %s <socket directory> <cmd>\n", argv[0]);
    exit(EXIT_FAILURE);
  }

  /* Setup listeners on domain sockets */
  for (ii = 0; ii < 3; ++ii) {
    memset(socket_paths[ii], 0, sizeof(socket_paths[ii]));
    nwritten = snprintf(socket_paths[ii], sizeof(socket_paths[ii]),
                        "%s/%s", argv[1], socket_names[ii]);
    if (nwritten >= sizeof(socket_paths[ii])) {
      fprintf(stderr, "Socket path too long\n");
      exit_status = 1;
      goto cleanup;
    }

    fds[ii] = create_unix_domain_listener(socket_paths[ii], backlog);

    DLOG("created listener, path=%s fd=%d", socket_paths[ii], fds[ii]);

    if (-1 == fds[ii]) {
      perrorf("Failed creating socket at %s:", socket_paths[ii]);
      exit_status = 1;
      goto cleanup;
    }

    set_cloexec(fds[ii]);
  }

  /*
   * Make sure iomux-spawn runs in an isolated process group such that
   * it is not affected by signals sent to its parent's process group.
   */
  setsid();

  child = child_create(argv + 2, argc - 2);

  printf("child_pid=%d\n", child->pid);
  fflush(stdout);

  /* Muxers for stdout/stderr */
  muxers[0] = muxer_alloc(fds[0], child->stdout[0], ring_buffer_size);
  muxers[1] = muxer_alloc(fds[1], child->stderr[0], ring_buffer_size);
  for (ii = 0; ii < 2; ++ii) {
    if (pthread_create(&muxer_threads[ii], NULL, run_muxer, muxers[ii])) {
      perrorf("Failed creating muxer thread:");
      exit_status = 1;
      goto cleanup;
    }

    DLOG("created muxer thread for socket=%s", socket_paths[ii]);
  }

  /* Status writer */
  barrier = barrier_alloc();
  sw = status_writer_alloc(fds[2], barrier);
  if (pthread_create(&sw_thread, NULL, run_status_writer, sw)) {
    perrorf("Failed creating muxer thread:");
    exit_status = 1;
    goto cleanup;
  }

  /* Wait for clients on stdout, stderr, and status */
  for (ii = 0; ii < 2; ++ii) {
    muxer_wait_for_client(muxers[ii]);
  }
  barrier_wait(barrier);

  child_continue(child);

  printf("child active\n");
  fflush(stdout);

  if (-1 == waitpid(child->pid, &child_status, 0)) {
    perrorf("Waitpid for child failed: ");
    exit_status = 1;
    goto cleanup;
  }

  DLOG("child exited, status = %d", WEXITSTATUS(child_status));

  /* Wait for status writer */
  status_writer_finish(sw, child_status);
  pthread_join(sw_thread, NULL);

  /* Wait for muxers */
  for (ii = 0; ii < 2; ++ii) {
    muxer_stop(muxers[ii]);
    pthread_join(muxer_threads[ii], NULL);
  }

  DLOG("all done, cleaning up and exiting");

cleanup:
  if (NULL != child) {
    child_free(child);
  }

  if (NULL != barrier) {
    barrier_free(barrier);
  }

  if (NULL != sw) {
    status_writer_free(sw);
  }

  for (ii = 0; ii < 2; ++ii) {
    if (NULL != muxers[ii]) {
      muxer_free(muxers[ii]);
    }
  }

  /* Close accept sockets and clean up paths */
  for (ii = 0; ii < 3; ++ii) {
    if (-1 != fds[ii]) {
      close(fds[ii]);
      unlink(socket_paths[ii]);
    }
  }

  return exit_status;
}
