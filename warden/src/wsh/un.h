#ifndef UN_H
#define UN_H 1

int un_listen(const char *path);
int un_connect(const char *path);
int un_send_fds(int fd, char *data, int datalen, int *fds, int fdslen);
int un_recv_fds(int fd, char *data, int datalen, int *fds, int fdslen);

#endif
