#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pty.h>

#include "pty.h"

/* Instead of using openpty from glibc, the following custom version is used
 * because we need to bypass dynamically loading the nsswitch libraries.
 * Executing glibc's openpty calls grantpt, which in turn depends on nsswitch
 * being loaded. The version of glibc inside a container may be different than
 * the version that wshd is compiled for, leading to undefined behavior. */
int openpty(int *master, int *slave, char *slave_name) {
  int rv;
  int lock;
  int pty;
  char buf[32];

  /* Open master */
  rv = open("/dev/ptmx", O_RDWR | O_NOCTTY);
  if (rv == -1) {
    return -1;
  }

  *master = rv;

  /* Figure out PTY number */
  pty = 0;
  rv = ioctl(*master, TIOCGPTN, &pty);
  if (rv == -1) {
    return -1;
  }

  rv = snprintf(buf, sizeof(buf), "/dev/pts/%d", pty);
  if (rv >= sizeof(buf)) {
    return -1;
  }

  /* Unlock slave before opening it */
  lock = 0;
  rv = ioctl(*master, TIOCSPTLCK, &lock);
  if (rv == -1) {
    return -1;
  }

  /* Open slave */
  rv = open(buf, O_RDWR | O_NOCTTY);
  if (rv == -1) {
    return -1;
  }

  *slave = rv;
  if (slave_name != NULL) {
    strcpy(slave_name, buf);
  }

  return 0;
}