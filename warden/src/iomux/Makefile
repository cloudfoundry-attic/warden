OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: iomux-spawn iomux-link

clean:
		rm -f *.o iomux-spawn test iomux-link

.PHONY: all clean

test: test.o ring_buffer.o util.o test_ring_buffer.o test_muxer.o muxer.o barrier.o status_writer.o test_status_writer.o dlog.o
		$(CC) -o $@ $^ -lpthread

iomux-spawn: iomux-spawn.o ring_buffer.o muxer.o status_writer.o child.o util.o barrier.o dlog.o
		$(CC) -o $@ $^ -lpthread

iomux-link: iomux-link.o pump.o util.o
		$(CC) -o $@ $^ -lpthread

%.o: %.c
		$(CC) -c -Wall -D_GNU_SOURCE $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<
