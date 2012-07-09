#include <arpa/inet.h>
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include "pump.h"
#include "util.h"

#define PUMP_SIZE 4096

typedef enum {
  STATE_OFFSET,
  STATE_DISCARD,
  STATE_PUMP
} pump_state_t;

void pump_setup(pump_t *pump, int src_fd, int dst_fd, uint32_t old_pos) {
  assert(NULL != pump);
  assert(src_fd >= 0);
  assert(dst_fd >= 0);

  memset(pump, 0, sizeof(*pump));

  pump->state = STATE_OFFSET;

  pump->pos     = 0;
  pump->old_pos = old_pos;

  pump->src_fd = src_fd;
  pump->dst_fd = dst_fd;
}

int pump_run(pump_t *pump) {
  uint8_t buf[PUMP_SIZE];
  uint8_t w_hup = 0, r_hup = 0;
  uint8_t *bufp = NULL, *buf_end = NULL;
  ssize_t  ncopy = 0, nread = 0, nwritten = 0;
  size_t ndiscard = 0;
  ptrdiff_t nremain = 0;

  assert(NULL != pump);

  nread = atomic_read(pump->src_fd, buf, sizeof(buf), &r_hup);

  bufp = buf;
  buf_end = buf + nread;

  while ((bufp != buf_end) && (!w_hup)) {
    nremain = buf_end - bufp;

    switch (pump->state) {
      case STATE_OFFSET:
        ncopy = MIN(nremain, sizeof(pump->pos) - pump->pos_off);

        memcpy(pump->pos_bytes + pump->pos_off, bufp, ncopy);

        pump->pos_off += ncopy;
        bufp += ncopy;

        if (pump->pos_off == sizeof(pump->pos)) {
          /* Have the offset, can proceed to data */
          memcpy(&pump->pos, pump->pos_bytes, sizeof(pump->pos_bytes));
          pump->pos = ntohl(pump->pos);
          pump->state = STATE_DISCARD;
        }
        break;

      case STATE_DISCARD:
        if (pump->pos >= pump->old_pos) {
          pump->state = STATE_PUMP;
        } else {
          ndiscard = MIN(pump->old_pos - pump->pos, nremain);
          bufp += ndiscard;
          pump->pos += ndiscard;
        }
        break;

      case STATE_PUMP:
        nwritten = atomic_write(pump->dst_fd, bufp, nremain, &w_hup);
        pump->pos += nwritten;
        bufp += nremain;
        break;

      default:
        /* NOTREACHED */
        assert(0);
        break;
    }
  }

  return (w_hup || r_hup);
}


