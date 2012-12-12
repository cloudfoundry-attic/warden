#ifndef UTIL_H
#define UTIL_H

#define fcntl_mix_cloexec(fd) fcntl_set_cloexec((fd), 1)
#define fcntl_mix_nonblock(fd) fcntl_set_nonblock((fd), 1)

void fcntl_set_cloexec(int fd, int on);
void fcntl_set_nonblock(int fd, int on);
int run(const char *p1, const char *p2);
void setproctitle(char **argv, const char *title);

#endif
