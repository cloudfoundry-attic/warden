OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: repquota

clean:
		rm -f *.o repquota

.PHONY: all clean

repquota: repquota.o
		$(CC) -o $@ $^ -lutil

%.o: %.c
		$(CC) -c -Wall -D_GNU_SOURCE $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<
