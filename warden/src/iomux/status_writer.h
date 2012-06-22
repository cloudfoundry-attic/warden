#ifndef STATUS_WRITER_H
#define STATUS_WRITER_H 1

#include <stdint.h>

typedef struct status_writer_s status_writer_t;

status_writer_t *status_writer_alloc(int accept_fd);

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
 * @param status Exit status of the child. Typically WEXITSTATUS(status).
 */
void status_writer_finish(status_writer_t *sw, uint8_t status);

void status_writer_free(status_writer_t *sw);
#endif
