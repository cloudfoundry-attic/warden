OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: wshd wshc

clean:
	rm -f *.o clone wshd wshc

install: all
	cp wshd wshc ../../root/linux/skeleton/bin/

.PHONY: all clean

wshd: wshd.o barrier.o mount.o un.o util.o msg.o
	$(CC) -o $@ $^ -lutil

wshc: wshc.o pump.o un.o util.o msg.o
	$(CC) -o $@ $^ -lutil

%.o: %.c
	$(CC) -c -Wall $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<

-include Makefile.dep

dep:
	$(CC) -MM *.c > Makefile.dep
