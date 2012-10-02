#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include "msg.h"
#include "pump.h"
#include "un.h"

void pump_loop(pump_t *p, int exit_status_fd, pump_pair_t *pp, int pplen) {
  int i, rv;

  for (;;) {
    pump_init(p);

    for (i = 0; i < pplen; i++) {
      pump_add_pair(p, &pp[i]);
    }

    if (exit_status_fd >= 0) {
      pump_add_fd(p, exit_status_fd, PUMP_READ | PUMP_EXCEPT);
    }

    do {
      rv = pump_select(p);
    } while (rv == -1 && errno == EINTR);

    if (rv == -1) {
      perror("select");
      abort();
    }

    for (i = 0; i < pplen; i++) {
      pump_pair_copy(&pp[i]);
    }

    if (pump_ready(p, exit_status_fd, PUMP_READ | PUMP_EXCEPT)) {
      int status;

      rv = read(exit_status_fd, &status, sizeof(status));
      if (rv < sizeof(status)) {
        /* Error, or short read. */
        perror("read");
        exit(255);
      }

      /* One more splice to make sure kernel buffers are emptied */
      for (i = 0; i < pplen; i++) {
        pump_pair_copy(&pp[i]);
      }

      exit(status);
    }
  }
}

static int pty_local_fd, pty_remote_fd;
static struct termios told, tnew;
static struct winsize wsz;

void tty_reset(void) {
  int rv;

  rv = tcsetattr(pty_local_fd, TCSANOW, &told);
  assert(rv != -1);
}

void tty__atexit(void) {
  tty_reset();
}

void tty_raw(void) {
  int rv;

  rv = tcgetattr(pty_local_fd, &told);
  assert(rv != -1);

  rv = atexit(tty__atexit);
  assert(rv != -1);

  tnew = told;
  cfmakeraw(&tnew);

  rv = tcsetattr(pty_local_fd, TCSANOW, &tnew);
  assert(rv != -1);
}

void tty_gwinsz(void) {
  int rv;

  rv = ioctl(pty_local_fd, TIOCGWINSZ, &wsz);
  assert(rv != -1);
}

void tty_swinsz(void) {
  int rv;

  rv = ioctl(pty_remote_fd, TIOCSWINSZ, &wsz);
  assert(rv != -1);
}

void tty__sigwinch(int sig) {
  tty_gwinsz();
  tty_swinsz();
}

void tty_winsz(void) {
  sighandler_t s;

  /* Setup handler for window size */
  s = signal(SIGWINCH, tty__sigwinch);
  assert(s != SIG_ERR);

  /* Figure out window size and forward it to the remote pty */
  tty_gwinsz();
  tty_swinsz();
}

int loop_interactive(int fd) {
  msg_response_t res;
  char buf[1024];
  size_t buflen = sizeof(buf);
  int fds[2];
  size_t fdslen = sizeof(fds)/sizeof(fds[0]);
  int rv;

  rv = un_recv_fds(fd, buf, buflen, fds, fdslen);
  if (rv <= 0) {
    perror("recvmsg");
    exit(255);
  }

  assert(rv == sizeof(res));
  memcpy(&res, buf, sizeof(res));

  pty_remote_fd = fds[0];
  pty_local_fd = STDIN_FILENO;

  tty_raw();
  tty_winsz();

  pump_t p;
  pump_pair_t pp[2];

  /* Use duplicates to decouple input/output */
  pump_pair_init(&pp[0], &p, STDIN_FILENO, dup(fds[0]));
  pump_pair_init(&pp[1], &p, dup(fds[0]), STDOUT_FILENO);

  pump_loop(&p, fds[1], pp, 2);

  return 0;
}

int loop_noninteractive(int fd) {
  msg_response_t res;
  char buf[1024];
  size_t buflen = sizeof(buf);
  int fds[4];
  size_t fdslen = sizeof(fds)/sizeof(fds[0]);
  int rv;

  rv = un_recv_fds(fd, buf, buflen, fds, fdslen);
  if (rv <= 0) {
    perror("recvmsg");
    exit(255);
  }

  assert(rv == sizeof(res));
  memcpy(&res, buf, sizeof(res));

  pump_t p;
  pump_pair_t pp[3];

  pump_pair_init(&pp[0], &p, STDIN_FILENO, fds[0]);
  pump_pair_init(&pp[1], &p, fds[1], STDOUT_FILENO);
  pump_pair_init(&pp[2], &p, fds[2], STDERR_FILENO);

  pump_loop(&p, fds[3], pp, 3);

  return 0;
}

int main(int argc, char **argv) {
  int fd, rv;
  msg_request_t req;

  if (argc < 2) {
    fprintf(stderr, "Usage: %s SOCKET\n", argv[0]);
    exit(1);
  }

  rv = un_connect(argv[1]);
  if (rv < 0) {
    perror("connect");
    exit(255);
  }

  fd = rv;

  msg_request_init(&req);

  if (isatty(STDIN_FILENO)) {
    req.tty = 1;
  } else {
    req.tty = 0;
  }

  rv = un_send_fds(fd, (char *)&req, sizeof(req), NULL, 0);
  if (rv <= 0) {
    perror("sendmsg");
    exit(255);
  }

  if (req.tty) {
    return loop_interactive(fd);
  } else {
    return loop_noninteractive(fd);
  }
}
