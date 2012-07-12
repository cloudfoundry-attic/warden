#ifndef CHILD_H
#define CHILD_H 1

#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

typedef struct child_s child_t;

struct child_s {
  char **argv;
  size_t argv_size;

  pid_t pid;

  int stdout[2];
  int stderr[2];

  int barrier[2];
};

/**
 * Forks off a child process that will execute the command specified by _argv_.
 *
 * NB: stdout/stderr of the child will be redirected to the pipes _stdout_ and
 *     _stderr_.
 */
child_t *child_create(char **argv, size_t argv_size);

/**
 * Unblocks the child process.
 */
void child_continue(child_t *child);

void child_free(child_t *child);

#endif
