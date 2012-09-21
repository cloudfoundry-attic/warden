#include <errno.h>
#include <fcntl.h>
#include <pty.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "console.h"
#include "util.h"

int console_open(console_t *c) {
  int rv;

  rv = openpty(&c->master, &c->slave, c->path, NULL, NULL);
  if (rv == -1) {
    fprintf(stderr, "openpty: %s\n", strerror(errno));
    return -1;
  }

  fcntl_mix_cloexec(c->master);
  fcntl_mix_cloexec(c->slave);

  return 0;

err:
  close(c->master);
  close(c->slave);
  return -1;
}

int console_mount(console_t *c, const char *path) {
  struct stat st;
  int rv;

  rv = stat(path, &st);
  if (rv == -1) {
    fprintf(stderr, "stat: %s\n", strerror(errno));
    return -1;
  }

  /* Mirror user/group */
  rv = chown(c->path, st.st_uid, st.st_gid);
  if (rv == -1) {
    fprintf(stderr, "chown: %s\n", strerror(errno));
    return -1;
  }

  /* Mirror permissions */
  rv = chmod(c->path, st.st_mode);
  if (rv == -1) {
    fprintf(stderr, "chmod: %s\n", strerror(errno));
    return -1;
  }

  /* Bind-mount path to console to specified path */
  rv = mount(c->path, path, NULL, MS_BIND, NULL);
  if (rv == -1) {
    fprintf(stderr, "mount: %s\n", strerror(errno));
    return -1;
  }

  return 0;
}

int console_log(console_t *c, const char *path) {
  int fd;

  fd = open(path, O_CREAT | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR);
  if (fd == -1) {
    fprintf(stderr, "open: %s\n", strerror(errno));
    goto err;
  }

  char buf[1024];
  int nread, nwritten, aux;

  while (1) {
    nread = read(c->master, buf, sizeof(buf));
    if (nread == -1) {
      fprintf(stderr, "read: %s\n", strerror(errno));
      goto err;
    } else if (nread == 0) {
      fprintf(stderr, "read: eof\n");
      goto err;
    }

    nwritten = 0;
    while (nwritten < nread) {
      aux = write(fd, buf + nwritten, nread - nwritten);
      if (aux == -1) {
        fprintf(stderr, "write: %s\n", strerror(errno));
        goto err;
      }

      nwritten += aux;
    }
  }

  return 0;

err:
  if (fd >= 0) close(fd);
  return -1;
}
