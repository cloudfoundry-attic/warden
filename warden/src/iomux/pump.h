#ifndef PUMP_H
#define PUMP_H 1

#include <stdint.h>

typedef struct {
  int      state;

  uint8_t  pos_bytes[4];
  uint8_t  pos_off;

  uint32_t old_pos;
  uint32_t pos;

  int      src_fd;
  int      dst_fd;
} pump_t;

void pump_setup(pump_t *pump, int src_fd, int dst_fd, uint32_t old_pos);

int pump_run(pump_t *pump);

#endif
