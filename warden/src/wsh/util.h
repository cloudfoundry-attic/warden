#ifndef UTIL_H
#define UTIL_H

void fcntl_mix_cloexec(int fd);
void fcntl_mix_nonblock(int fd);
int run(const char *p1, const char *p2);

#endif
