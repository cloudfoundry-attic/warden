#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include "util.h"

#define ATOMIC_IO(func, fd, buf, count, hup) do {                       \
  ssize_t nbytes_tot = 0;                                               \
  ssize_t nbytes_cur = 0;                                               \
  uint8_t done = 0;                                                     \
  if (NULL != hup) {                                                    \
    *(hup) = 0;                                                         \
  }                                                                     \
                                                                        \
  while (!done) {                                                       \
    nbytes_cur = (func)((fd), (buf) + nbytes_tot, count - nbytes_tot);  \
    if (-1 == nbytes_cur) {                                             \
      switch (errno) {                                                  \
        case EAGAIN:                                                    \
          done = 1;                                                     \
          break;                                                        \
        case EINTR:                                                     \
          break;                                                        \
        case EPIPE:                                                     \
          if (NULL != hup) {                                            \
            *(hup) = 1;                                                 \
          }                                                             \
          done = 1;                                                     \
          break;                                                        \
        case ECONNRESET:                                                \
          if (NULL != hup) {                                            \
            *(hup) = 1;                                                 \
          }                                                             \
          done = 1;                                                     \
          break;                                                        \
        default:                                                        \
          perror("atomic_io");                                          \
          assert(0);                                                    \
          break;                                                        \
      }                                                                 \
    } else if (0 == nbytes_cur) {                                       \
      if (NULL != hup) {                                                \
        *(hup) = 1;                                                     \
      }                                                                 \
      done = 1;                                                         \
    } else {                                                            \
      nbytes_tot += nbytes_cur;                                         \
      done = (nbytes_tot == count);                                     \
    }                                                                   \
  }                                                                     \
  return nbytes_tot;                                                    \
} while (0);

ssize_t atomic_read(int fd, void *buf, size_t count, uint8_t *hup) {
  ATOMIC_IO(read, fd, buf, count, hup);
}

ssize_t atomic_write(int fd, const void *buf, size_t count, uint8_t *hup) {
  ATOMIC_IO(write, fd, buf, count, hup);
}

void set_nonblocking(int fd) {
  int flags = 0;

  flags = fcntl(fd, F_GETFL, 0);
  if (flags == -1) {
    perror("fcntl");
    abort();
  }

  if (-1 == fcntl(fd, F_SETFL, flags | O_NONBLOCK)) {
    perror("fcntl");
    abort();
  }
}

void set_cloexec(int fd) {
  if (-1 == fcntl(fd, F_SETFD, FD_CLOEXEC)) {
    perror("fcntl");
    abort();
  }
}

void checked_lock(pthread_mutex_t *lock) {
  assert(NULL != lock);

  if (-1 == pthread_mutex_lock(lock)) {
    perror("pthread_mutex_lock");
    assert(0);
  }
}

void checked_unlock(pthread_mutex_t *lock) {
  assert(NULL != lock);

  if (-1 == pthread_mutex_unlock(lock)) {
    perror("pthread_mutex_unlock");
    assert(0);
  }
}

int create_unix_domain_listener(const char *path, int backlog) {
  struct sockaddr_un addr;
  int fd = 0;

  assert(NULL != path);

  fd = socket(PF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }

  unlink(path);

  memset(&addr, 0, sizeof(struct sockaddr_un));

  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, path, MIN(strlen(path), sizeof(addr.sun_path)));

  if (0 != bind(fd, (struct sockaddr *) &addr, sizeof(struct sockaddr_un))) {
    return -1;
  }

  if (0 != listen(fd, backlog)) {
    return -1;
  }

  if (0 != chmod(path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH)) {
    return -1;
  }

  return fd;
}

int unix_domain_connect(const char *path) {
  struct sockaddr_un addr;
  int fd = 0;

  assert(NULL != path);

  fd = socket(PF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }

  memset(&addr, 0, sizeof(struct sockaddr_un));

  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, path, MIN(strlen(path), sizeof(addr.sun_path)));

  if (0 != connect(fd, (struct sockaddr *) &addr, sizeof(struct sockaddr_un))) {
    return -1;
  }

  return fd;
}

uint8_t wait_readable_or_stop(int read_fd, int stop_fd) {
  uint8_t done   = 0;
  int     nfds   = 0;
  uint8_t events = 0;
  fd_set  read_fds;

  assert(read_fd >= 0);
  assert(stop_fd >= 0);

  nfds = MAX(read_fd, stop_fd) + 1;

  FD_ZERO(&read_fds);
  FD_SET(read_fd, &read_fds);
  FD_SET(stop_fd, &read_fds);

  do {
    if (-1 != select(nfds, &read_fds, NULL, NULL, NULL)) {
      if (FD_ISSET(read_fd, &read_fds)) {
        events |= MUXER_READABLE;
      }

      if (FD_ISSET(stop_fd, &read_fds)) {
        events |= MUXER_STOP;
      }

      done = 1;
    } else {
      if (EINTR != errno) {
        perror("select()");
        assert(0);
      }
    }
  } while (!done);

  return events;
}

void perrorf(const char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);

  fprintf(stderr, " %s\n", strerror(errno));
}
