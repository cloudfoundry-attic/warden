#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <syscall.h>
#include <unistd.h>

#include "dlog.h"
#include "util.h"

static pthread_mutex_t stdout_lock = PTHREAD_MUTEX_INITIALIZER;

void _dlog(const char *file, const char *func, int line,
           const char *format, ...) {
  va_list ap;

  va_start(ap, format);

  checked_lock(&stdout_lock);

  printf("thread=%ld %s:%s:%d -- ", syscall(SYS_gettid), file, func, line);
  vprintf(format, ap);
  printf("\n");
  fflush(stdout);

  checked_unlock(&stdout_lock);

  va_end(ap);
}

