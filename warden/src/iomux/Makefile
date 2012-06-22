OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: iomux-spawn

clean:
		rm -f *.o iomux-spawn test

.PHONY: all clean

test: test.o ring_buffer.o util.o test_ring_buffer.o test_muxer.o muxer.o barrier.o status_writer.o test_status_writer.o
		$(CC) -lpthread -o $@ $^

iomux-spawn: iomux-spawn.o ring_buffer.o muxer.o status_writer.o child.o util.o
		$(CC) -lpthread -o $@ $^

%.o: %.c
		$(CC) -c -Wall -D_GNU_SOURCE $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<
