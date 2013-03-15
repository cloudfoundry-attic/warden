#ifndef PTY_H
#define PTY_H

#define openpty __wshd_openpty

int openpty(int *master, int *slave, char *name);

#endif
