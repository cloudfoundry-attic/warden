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
  int              fds[3], ii, exit_status = 0;
  pthread_t        sw_thread, muxer_threads[2];
  char             socket_paths[3][PATH_MAX + 1];
  char             *socket_names[3] = { "stdout.sock", "stderr.sock", "status.sock" };

  if (argc < 3) {
    fprintf(stderr, "Usage: %s <socket directory> <cmd>\n", argv[0]);
    exit(EXIT_FAILURE);
  }

  /* Setup listeners on domain sockets */
  for (ii = 0; ii < 3; ++ii) {
    fds[ii] = -1;

    memset(socket_paths[ii], 0, PATH_MAX + 1);
    snprintf(socket_paths[ii], PATH_MAX + 1, "%s/%s", argv[1], socket_names[ii]);

    fds[ii] = create_unix_domain_listener(socket_paths[ii], backlog);

    if (-1 == fds[ii]) {
      fprintf(stderr, "Failed creating socket at %s:\n", socket_paths[ii]);
      perror("");
      exit_status = 1;
      goto cleanup;
    }
  }

  child = child_create(argv + 2, argc - 2);

  /* Muxer for stdout/stderr */
  muxers[0] = muxer_alloc(fds[0], child->stdout[0], ring_buffer_size);
  muxers[1] = muxer_alloc(fds[1], child->stderr[0], ring_buffer_size);
  for (ii = 0; ii < 2; ++ii) {
    if (pthread_create(&muxer_threads[ii], NULL, run_muxer, muxers[ii])) {
      fprintf(stderr, "Failed creating muxer thread:\n");
      perror("pthread_create()");
      exit_status = 1;
      goto cleanup;
    }
  }

  /* Status writer */
  sw = status_writer_alloc(fds[2]);
  if (pthread_create(&sw_thread, NULL, run_status_writer, sw)) {
    fprintf(stderr, "Failed creating status writer thread:\n");
    exit_status = 1;
    goto cleanup;
  }

  child_continue(child);

  if (-1 == waitpid(child->pid, &child_status, 0)) {
    fprintf(stderr, "Waitpid for child failed: ");
    perror("waitpid()");
    exit_status = 1;
    goto cleanup;
  }

  /* Wait for status writer */
  status_writer_finish(sw, WEXITSTATUS(child_status));
  pthread_join(sw_thread, NULL);

  /* Wait for muxers */
  for (ii = 0; ii < 2; ++ii) {
    muxer_stop(muxers[ii]);
    pthread_join(muxer_threads[ii], NULL);
  }

cleanup:
  if (NULL != child) {
    child_free(child);
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
