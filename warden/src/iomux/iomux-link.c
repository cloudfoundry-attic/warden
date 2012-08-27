#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <unistd.h>

#include "pump.h"
#include "status_reader.h"
#include "util.h"

#define INTERNAL_ERROR_STATUS 255

/* These must be visible to the signal handlers */
static char *saved_posns_path = NULL;
static pump_t pumps[2];

static int read_saved_posns(const char *path, uint32_t *saved_posns, size_t size) {
  FILE   *f     = NULL;
  int     ii    = 0;
  size_t  nread = 0;

  f = fopen(path, "r");
  if (NULL == f) {
    if (ENOENT == errno) {
      for (ii = 0; ii < size; ++ii) {
        saved_posns[ii] = 0;
      }
      return 0;
    } else {
      return 1;
    }
  }

  for (ii = 0; ii < size; ++ii) {
    nread = fread(saved_posns + ii, sizeof(uint32_t), 1, f);
    if (nread < 1) {
      fclose(f);
      return 1;
    }

    saved_posns[ii] = ntohl(saved_posns[ii]);
  }

  fclose(f);

  return 0;
}

static int write_posns(const char *path, uint32_t *saved_posns, size_t size) {
  FILE     *f        = NULL;
  size_t    nwritten = 0;
  int       ii       = 0;
  uint32_t  pos      = 0;

  f = fopen(path, "w+");
  if (NULL == f) {
    return 1;
  }

  for (ii = 0; ii < size; ++ii) {
    pos = htonl(saved_posns[ii]);
    nwritten = fwrite(&pos, sizeof(uint32_t), 1, f);
    if (nwritten < 1) {
      fclose(f);
      return 1;
    }
  }

  fclose(f);

  return 0;
}

static void save_posns(void) {
  uint32_t saved_posns[2]  = {0, 0};
  int ii = 0;

  if (NULL != saved_posns_path) {
    for (ii = 0; ii < 2; ++ii) {
      saved_posns[ii] = pumps[ii].pos;
    }
    write_posns(saved_posns_path, saved_posns, 2);
  }
}

static void sighandler(int signum) {
  save_posns();
  exit(0);
}

static void usage(const char *name) {
  fprintf(stderr, "Usage: %s [-w <saved position path>] <socket directory>\n",
          name);
  exit(INTERNAL_ERROR_STATUS);
}

static int parse_args(int argc, char *argv[], char **saved_posns_path,
                      char **sockets_dir) {
  int opt = -1;

  while ((opt = getopt(argc, argv, "w:")) != -1) {
    switch (opt) {
      case 'w':
        *saved_posns_path = optarg;
        break;

      default:
        return 1;
    }
  }

  if (optind != argc -1) {
    return 1;
  }

  *sockets_dir = argv[optind];

  return 0;
}

int main(int argc, char *argv[]) {
  int      exit_status     = INTERNAL_ERROR_STATUS;
  char    *socket_names[3] = { "stdout.sock", "stderr.sock", "status.sock" };
  char     socket_paths[3][PATH_MAX + 1];
  int      fds[3]          = {-1, -1, -1}, nfds = 0, ii = 0, nwritten = 0;
  uint8_t  done            = 0, hup = 0;
  fd_set   readable_fds;
  uint32_t saved_posns[2]  = {0, 0};
  char    *sockets_dir = NULL;
  int      signals[2] = {SIGTERM, SIGINT};
  status_reader_t status_reader;
  struct sigaction sa;

  if (parse_args(argc, argv, &saved_posns_path, &sockets_dir)) {
    usage(argv[0]);
  }

  if (NULL != saved_posns_path) {
    if (read_saved_posns(saved_posns_path, saved_posns, 2)) {
      fprintf(stderr, "Failed reading saved position from %s\n",
              saved_posns_path);
      goto cleanup;
    }
  }

  /* Connect to domain sockets */
  for (ii = 0; ii < 3; ++ii) {
    memset(socket_paths[ii], 0, sizeof(socket_paths[ii]));
    nwritten = snprintf(socket_paths[ii], sizeof(socket_paths[ii]),
                        "%s/%s", sockets_dir, socket_names[ii]);
    if (nwritten >= sizeof(socket_paths[ii])) {
      fprintf(stderr, "Socket path too long\n");
      goto cleanup;
    }

    fds[ii] = unix_domain_connect(socket_paths[ii]);
    if (-1 == fds[ii]) {
      perrorf("Failed connecting to %s: ", socket_paths[ii]);
      goto cleanup;
    }

    set_nonblocking(fds[ii]);
  }

  pump_setup(&pumps[0], fds[0], STDOUT_FILENO, saved_posns[0]);
  pump_setup(&pumps[1], fds[1], STDERR_FILENO, saved_posns[1]);
  status_reader_init(&status_reader, fds[2]);

  for (ii = 0; ii < 2; ++ii) {
    sa.sa_flags = 0;
    sa.sa_handler = sighandler;
    sigemptyset(&sa.sa_mask);
    if (-1 == sigaction(signals[ii], &sa, NULL)) {
      perror("Failed installing signal handler");
      goto cleanup;
    }
  }

  /* Loop until all connections are broken or an error occurs */
  while (1) {
    FD_ZERO(&readable_fds);

    nfds = 0;
    done = 1;

    for (ii = 0; ii < 3; ++ii) {
      if (-1 != fds[ii]) {
        nfds = MAX(nfds, fds[ii]) + 1;
        FD_SET(fds[ii], &readable_fds);
        done = 0;
      }
    }

    if (done) {
      break;
    }

    if (-1 != select(nfds, &readable_fds, NULL, NULL, NULL)) {
      /* Pump stderr/stdout */
      for (ii = 0; ii < 2; ++ii) {
        if (fds[ii] > 0 && FD_ISSET(fds[ii], &readable_fds)) {
          /* Stop watching for reads if a hup occurred */
          if (pump_run(&pumps[ii])) {
            close(fds[ii]);
            fds[ii] = -1;
          }
        }
      }

      /* Handle status */
      if (fds[2] > 0 && FD_ISSET(fds[2], &readable_fds)) {
        if (status_reader_run(&status_reader, &hup)) {
          if (!hup) {
            if (WIFEXITED(status_reader.status)) {
              exit_status = WEXITSTATUS(status_reader.status);
            }
          }

          close(fds[2]);
          fds[2] = -1;
        }
      }
    } else {
      if (EINTR != errno) {
        perror("select()");
        break;
      }
    }
  }

  save_posns();

cleanup:
  for (ii = 0; ii < 3; ++ii) {
    if (-1 != fds[ii]) {
      close(fds[ii]);
    }
  }

  return exit_status;
}
