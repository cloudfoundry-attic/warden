#ifndef UTIL_H
#define UTIL_H 1

#include <linux/limits.h>
#include <pthread.h>
#include <sys/types.h>
#include <stddef.h>
#include <stdint.h>

#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#define MAX(a, b) (((a) > (b)) ? (a) : (b))

#define MUXER_READABLE 1
#define MUXER_STOP 2

/**
 * Reads until _count_ bytes have been read or _fd_ would block.
 */
ssize_t atomic_read(int fd, void *buf, size_t count, uint8_t *hup);

/**
 * Writes until _count_ bytes have been written or _fd_ would block.
 */
ssize_t atomic_write(int fd, const void *buf, size_t count, uint8_t *hup);

void set_nonblocking(int fd);

void set_cloexec(int fd);

void checked_lock(pthread_mutex_t *lock);

void checked_unlock(pthread_mutex_t *lock);

int create_unix_domain_listener(const char *path, int backlog);

int unix_domain_connect(const char *path);

uint8_t wait_readable_or_stop(int read_fd, int stop_fd);

void perrorf(const char *fmt, ...);

#endif
