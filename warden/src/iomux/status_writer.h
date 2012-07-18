#ifndef STATUS_WRITER_H
#define STATUS_WRITER_H 1

#include <stdint.h>

#include "barrier.h"

typedef struct status_writer_s status_writer_t;

/**
 * Allocates a new status writer.
 *
 * @param accept_fd
 * @param barrier   If supplied, this barrier will be lifted once a client has
 *                  connected.
 */
status_writer_t *status_writer_alloc(int accept_fd, barrier_t *barrier);

/**
 * Starts the status writer. This blocks until someone calls
 * status_writer_finish().
 */
void status_writer_run(status_writer_t *sw);

/**
 * Tells the status writer that the child has completed. The status
 * writer in turn writes out the supplied child status to any connected clients.
 *
 * @param sw
 * @param status Exit status of the child.
 */
void status_writer_finish(status_writer_t *sw, int status);

void status_writer_free(status_writer_t *sw);
#endif
