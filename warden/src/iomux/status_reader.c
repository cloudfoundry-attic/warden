#include <arpa/inet.h>
#include <assert.h>
#include <string.h>

#include "status_reader.h"
#include "util.h"

void status_reader_init(status_reader_t *reader, int fd) {
  assert(NULL != reader);
  assert(fd >= 0);

  memset(reader->buf, 0, sizeof(reader->buf));
  reader->off    = 0;
  reader->status = -1;
  reader->fd     = fd;
}

int status_reader_run(status_reader_t *reader, uint8_t *hup) {
  uint32_t in_status;
  int done = 0;

  reader->off += atomic_read(reader->fd, reader->buf + reader->off,
                             sizeof(reader->buf) - reader->off, hup);

  if (reader->off >= sizeof(reader->buf)) {
    memcpy(&in_status, reader->buf, sizeof(reader->buf));
    reader->status = ntohl(in_status);
    done = 1;
  }

  if (*hup) {
    done = 1;
  }

  return done;
}

