#ifndef STATUS_WRITER_H
#define STATUS_WRITER_H 1

typedef struct status_writer_s status_writer_t;

status_writer_t *status_writer_alloc(int accept_fd);

void status_writer_run(status_writer_t *sw);

void status_writer_finish(status_writer_t *sw, int status);

void status_writer_free(status_writer_t *sw);
#endif
