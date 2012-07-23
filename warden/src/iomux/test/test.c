#include "test_muxer.h"
#include "test_ring_buffer.h"
#include "test_status_writer.h"

int main(int argc, char **argv) {
  test_ring_buffer();
  test_muxer();
  test_status_writer();
  return 0;
}
