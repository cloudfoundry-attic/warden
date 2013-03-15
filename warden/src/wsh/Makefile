OPTIMIZATION?=-O0
DEBUG?=-g -ggdb -rdynamic

all: wshd wsh

clean:
	rm -f *.o clone wshd wsh

install: all
	cp wshd wsh ../../root/linux/skeleton/bin/

.PHONY: all clean

wshd: wshd.o barrier.o mount.o un.o util.o msg.o pwd.o pty.o
	$(CC) -static -o $@ $^ -lutil

wsh: wsh.o pump.o un.o util.o msg.o pwd.o
	$(CC) -static -o $@ $^ -lutil

%.o: %.c
	$(CC) -c -Wall $(OPTIMIZATION) $(DEBUG) $(CFLAGS) $<

-include Makefile.dep

dep:
	$(CC) -MM *.c > Makefile.dep
