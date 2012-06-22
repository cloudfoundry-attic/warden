#ifndef RING_BUFFER_H
#define RING_BUFFER_H 1

#include <stddef.h>
#include <stdint.h>

typedef struct ring_buffer_s ring_buffer_t;

ring_buffer_t *ring_buffer_alloc(size_t capacity);

/**
 * Writes data to the supplied ring buffer.
 *
 */
void ring_buffer_append(ring_buffer_t *buf, const uint8_t *data, size_t size);

/**
 * Reads _size_ bytes from the buffer into _dst_, starting at offset _start_.
 *
 * @param buf   The buffer being read from.
 * @param start Offset into the buffer that specifies where to start reading.
 * @param dst   Where to store the bytes
 * @param size  How many bytes to read
 *
 * @return Number of bytes read
 */
size_t ring_buffer_read(const ring_buffer_t *buf, size_t start, uint8_t *dst,
                        size_t size);

/**
 * Returns a copy of the ring buffer.
 *
 * NB: Caller is responsible for freeing the returned buffer.
 */
uint8_t *ring_buffer_dup(const ring_buffer_t *buf);

size_t ring_buffer_size(const ring_buffer_t *buf);

void ring_buffer_free(ring_buffer_t *buf);

#endif
