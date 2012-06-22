#include <assert.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include "ring_buffer.h"
#include "test_util.h"
#include "util.h"

static void test_ring_buffer_read_write(void) {
  ring_buffer_t *rb           = NULL;
  uint8_t       *str          = (uint8_t *) "AAAABBBBCCCC";
  size_t         str_size     = 12;
  size_t         buf_capacity = 8;
  size_t         bytes_read   = 0;
  uint8_t        read_buf[buf_capacity];

  rb = ring_buffer_alloc(buf_capacity);

  /* Write less than capacity */
  ring_buffer_append(rb, str, 4);

  /* Verify we can read it back */
  bytes_read = ring_buffer_read(rb, 0, read_buf, buf_capacity);
  TEST_CHECK(bytes_read == 4);
  TEST_CHECK(!memcmp(read_buf, "AAAA", bytes_read));

  /* Write a string that causes the buffer to wrap */
  ring_buffer_append(rb, str + 4, str_size - 4);

  /* Verify we can read it back */
  bytes_read = ring_buffer_read(rb, 0, read_buf, str_size - 4);
  TEST_CHECK(bytes_read == str_size - 4);
  TEST_CHECK(!memcmp(read_buf, "BBBBCCCC", bytes_read));

  /* Verify we can read something from the middle of the buffer */
  bytes_read = ring_buffer_read(rb, 2, read_buf, 4);
  TEST_CHECK(bytes_read == 4);
  TEST_CHECK(!memcmp(read_buf, "BBCC", bytes_read));

  /* Verify we only read what is available */
  bytes_read = ring_buffer_read(rb, 4, read_buf, 8);
  TEST_CHECK(bytes_read == 4);
  TEST_CHECK(!memcmp(read_buf, "CCCC", bytes_read));

  /* Write something larger than the capacity */
  ring_buffer_append(rb, str, str_size);

  /* Verify the correct substring is written */
  bytes_read = ring_buffer_read(rb, 0, read_buf, buf_capacity);
  TEST_CHECK(bytes_read == buf_capacity);
  TEST_CHECK(!memcmp(read_buf, "BBBBCCCC", bytes_read));

  ring_buffer_free(rb);
}

void test_ring_buffer(void) {
  test_ring_buffer_read_write();
}
