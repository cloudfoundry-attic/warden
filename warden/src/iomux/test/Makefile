OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic
VPATH=../
all: test

clean:
		rm -f *.o test

.PHONY: all clean

test: test.o ring_buffer.o util.o test_ring_buffer.o test_muxer.o muxer.o barrier.o status_writer.o status_reader.o test_status_writer.o dlog.o
		$(CC) -o $@ $^ -lpthread

%.o: %.c
		$(CC) -c -Wall -D_GNU_SOURCE -I../ $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<
