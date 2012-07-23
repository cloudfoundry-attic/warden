OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: iomux-spawn iomux-link

clean:
		rm -f *.o iomux-spawn iomux-link
		cd test && $(MAKE) $@

.PHONY: all clean

test:
		cd test && $(MAKE) $@

iomux-spawn: iomux-spawn.o ring_buffer.o muxer.o status_writer.o child.o util.o barrier.o dlog.o
		$(CC) -o $@ $^ -lpthread

iomux-link: iomux-link.o pump.o status_reader.o util.o
		$(CC) -o $@ $^ -lpthread

%.o: %.c
		$(CC) -c -Wall -D_GNU_SOURCE $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<
