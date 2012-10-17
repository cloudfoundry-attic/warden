OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: closefds

clean:
	rm -f *.o closefds

install: all
	# noop

.PHONY: all clean

closefds: closefds.o
	$(CC) -o $@ $^

%.o: %.c
	$(CC) -c -Wall $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<
