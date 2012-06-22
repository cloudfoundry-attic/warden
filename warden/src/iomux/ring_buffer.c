#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ring_buffer.h"
#include "util.h"

struct ring_buffer_s {
  size_t capacity;     /* Total size of data */
  size_t size;         /* How many bytes are currently stored in data */
  size_t start;        /* Offset in data of the first logical byte */
  uint8_t data[];
};

/**
 * Translates a logical index in the ringbuffer (assuming 0 is the oldest byte
 * and size - 1 is the newest byte) into a raw offset in the underlying array.
 */
static inline size_t log_to_raw(const ring_buffer_t *buf, size_t off) {
  if (buf->size < buf->capacity) {
    return off;
  } else {
    return (buf->start + off) % buf->capacity;
  }
}

ring_buffer_t *ring_buffer_alloc(size_t capacity) {
  ring_buffer_t *buf = NULL;

  assert(capacity > 0);

  buf = calloc(sizeof(*buf) + capacity, sizeof(uint8_t));
  assert(NULL != buf);

  buf->capacity = capacity;

  return buf;
}

void ring_buffer_append(ring_buffer_t *buf, const uint8_t *data, size_t size) {
  size_t off = 0;
  size_t nremain = size;
  size_t nto_copy = 0;

  assert(NULL != buf);
  assert(NULL != data);

  if (0 == size) {
    return;
  }

  /* Don't waste time copying bytes that would be overwritten */
  if (size > buf->capacity) {
    off = size - buf->capacity;
    nremain = buf->capacity;
  }

  while (nremain > 0) {
    nto_copy = MIN(nremain, buf->capacity - buf->start);

    memcpy(buf->data + buf->start, data + off, nto_copy);

    buf->size = MIN(buf->size + nto_copy, buf->capacity);
    buf->start = (buf->start + nto_copy) % buf->capacity;

    off += nto_copy;
    nremain -= nto_copy;
  }
}

size_t ring_buffer_read(const ring_buffer_t *buf, size_t start, uint8_t *dst,
                        size_t size) {
  size_t ncopied = 0;
  size_t nremain = 0;
  size_t nto_copy = 0;

  assert(NULL != buf);
  assert(NULL != dst);
  assert(start <= buf->size);

  nremain = MIN(buf->size - start, size);

  while (nremain > 0) {
    nto_copy = MIN(nremain, buf->capacity - log_to_raw(buf, start + ncopied));

    memcpy(dst + ncopied,
           buf->data + log_to_raw(buf, start + ncopied),
           nto_copy);

    nremain -= nto_copy;
    ncopied += nto_copy;
  }

  return ncopied;
}

uint8_t *ring_buffer_dup(const ring_buffer_t *buf) {
  uint8_t *ret = NULL;

  if (buf->size == 0) {
    return NULL;
  }

  ret = malloc(buf->size);
  assert(NULL != buf);

  ring_buffer_read(buf, 0, ret, buf->size);

  return ret;
}

size_t ring_buffer_size(const ring_buffer_t *buf) {
  assert(NULL != buf);

  return buf->size;
}

void ring_buffer_free(ring_buffer_t *buf) {
  assert(NULL != buf);

  free(buf);
}
