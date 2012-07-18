#ifndef STATUS_READER_H
#define STATUS_READER_H 1

#include <stdint.h>

typedef struct status_reader_s status_reader_t;

struct status_reader_s {
  int off;
  uint8_t buf[4];
  int status;
  int fd;
};

void status_reader_init(status_reader_t *reader, int fd);

int status_reader_run(status_reader_t *reader, uint8_t *hup);

#endif
