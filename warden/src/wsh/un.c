#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "un.h"
#include "util.h"

int un__socket() {
  int fd;

  if ((fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
    perror("socket");
    exit(1);
  }

  return fd;
}

int un_listen(const char *path) {
  int fd;
  struct sockaddr_un sa;

  fd = un__socket();

  sa.sun_family = AF_UNIX;
  assert(strlen(path) < sizeof(sa.sun_path));
  strcpy(sa.sun_path, path);
  unlink(sa.sun_path);

  fcntl_mix_cloexec(fd);

  if (bind(fd, (struct sockaddr *)&sa, sizeof(sa)) == -1) {
    perror("bind");
    exit(1);
  }

  if (listen(fd, 5) == -1) {
    perror("listen");
    exit(1);
  }

  return fd;
}

int un_connect(const char *path) {
  int fd;
  struct sockaddr_un sa;
  int rv;

  fd = un__socket();

  sa.sun_family = AF_UNIX;
  assert(strlen(path) < sizeof(sa.sun_path));
  strcpy(sa.sun_path, path);

  rv = connect(fd, (struct sockaddr *)&sa, sizeof(sa));
  if (rv == -1) {
    close(fd);
    return rv;
  }

  return fd;
}

int un_send_fds(int fd, char *data, int datalen, int *fds, int fdslen) {
  struct msghdr mh;
  struct cmsghdr *cmh = NULL;
  char *buf;
  size_t buflen = CMSG_SPACE(sizeof(int) * fdslen);
  struct iovec iov[1];

  buf = malloc(buflen);
  assert(buf != NULL);

  memset(&mh, 0, sizeof(mh));

  mh.msg_control = buf;
  mh.msg_controllen = buflen;
  mh.msg_iov = iov;
  mh.msg_iovlen = 1;
  iov[0].iov_base = data;
  iov[0].iov_len = datalen;

  cmh = CMSG_FIRSTHDR(&mh);
  cmh->cmsg_level = SOL_SOCKET;
  cmh->cmsg_type = SCM_RIGHTS;
  cmh->cmsg_len = CMSG_LEN(sizeof(int) * fdslen);
  memcpy(CMSG_DATA(cmh), fds, sizeof(int) * fdslen);
  mh.msg_controllen = cmh->cmsg_len;

  int rv;

  do {
    rv = sendmsg(fd, &mh, 0);
  } while (rv == -1 && errno == EINTR);

  free(buf);

  return rv;
}

int un_recv_fds(int fd, char *data, int datalen, int *fds, int fdslen) {
  struct msghdr mh;
  struct cmsghdr *cmh = NULL;
  char *buf;
  size_t buflen = CMSG_SPACE(sizeof(int) * fdslen);
  struct iovec iov[1];

  buf = malloc(buflen);
  assert(buf != NULL);

  memset(&mh, 0, sizeof(mh));

  mh.msg_control = buf;
  mh.msg_controllen = buflen;
  mh.msg_iov = iov;
  mh.msg_iovlen = 1;
  iov[0].iov_base = data;
  iov[0].iov_len = datalen;

  int rv;

  do {
    rv = recvmsg(fd, &mh, 0);
  } while (rv == -1 && (errno == EINTR || errno == EAGAIN));

  if (rv == -1) {
    goto done;
  }

  cmh = CMSG_FIRSTHDR(&mh);
  assert(cmh != NULL);
  assert(cmh->cmsg_level == SOL_SOCKET);
  assert(cmh->cmsg_type == SCM_RIGHTS);
  assert(cmh->cmsg_len == CMSG_LEN(sizeof(int) * fdslen));

  int *fds_ = (int *)CMSG_DATA(cmh);
  int i;

  for (i = 0; i < fdslen; i++) {
    fds[i] = fds_[i];
  }

done:
  free(buf);

  return rv;
}
