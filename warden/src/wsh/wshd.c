#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#include "barrier.h"
#include "msg.h"
#include "mount.h"
#include "un.h"
#include "util.h"

typedef struct wshd_s wshd_t;

struct wshd_s {
  int argc;
  char **argv;

  /* Path to directory where server socket is placed */
  const char *run_path;

  /* Path to directory containing hooks */
  const char *lib_path;

  /* Path to directory that will become root in the new mount namespace */
  const char *root_path;

  /* Process title */
  const char *title;

  /* File descriptor of listening socket */
  int fd;

  barrier_t barrier_parent;
  barrier_t barrier_child;
  pid_t pid;

  /* Map pids to exit status fds */
  int *pid_to_fd;
  size_t pid_to_fd_len;
};

int wshd__usage(wshd_t *w) {
  fprintf(stderr, "Usage: %s OPTION...\n", w->argv[0]);
  fprintf(stderr, "\n");

  fprintf(stderr, "  --run PATH   "
    "Directory where server socket is placed"
    "\n");

  fprintf(stderr, "  --lib PATH   "
    "Directory containing hooks"
    "\n");

  fprintf(stderr, "  --root PATH  "
    "Directory that will become root in the new mount namespace"
    "\n");

  fprintf(stderr, "  --title NAME "
    "Process title"
    "\n");

  return 0;
}

int wshd__getopt(wshd_t *w) {
  int i = 1;
  int j = w->argc - i;

  while (i < w->argc) {
    if (j >= 2) {
      if (strcmp("--run", w->argv[i]) == 0) {
        w->run_path = strdup(w->argv[i+1]);
      } else if (strcmp("--lib", w->argv[i]) == 0) {
        w->lib_path = strdup(w->argv[i+1]);
      } else if (strcmp("--root", w->argv[i]) == 0) {
        w->root_path = strdup(w->argv[i+1]);
      } else if (strcmp("--title", w->argv[i]) == 0) {
        w->title = strdup(w->argv[i+1]);
      } else {
        goto invalid;
      }

      i += 2;
      j -= 2;
    } else if (j == 1) {
      if (strcmp("-h", w->argv[i]) == 0 ||
          strcmp("--help", w->argv[i]) == 0)
      {
        wshd__usage(w);
        return -1;
      } else {
        goto invalid;
      }
    } else {
      assert(NULL);
    }
  }

  return 0;

invalid:
  fprintf(stderr, "%s: invalid option -- %s\n", w->argv[0], w->argv[i]);
  fprintf(stderr, "Try `%s --help' for more information.\n", w->argv[0]);
  return -1;
}

void assert_directory(const char *path) {
  int rv;
  struct stat st;

  rv = stat(path, &st);
  if (rv == -1) {
    fprintf(stderr, "stat(\"%s\"): %s\n", path, strerror(errno));
    exit(1);
  }

  if (!S_ISDIR(st.st_mode)) {
    fprintf(stderr, "stat(\"%s\"): %s\n", path, "No such directory");
    exit(1);
  }
}

void child_pid_to_fd_add(wshd_t *w, pid_t pid, int fd) {
  int len = w->pid_to_fd_len;
  int diff = 2 * sizeof(int);

  /* Store a copy */
  fd = dup(fd);
  if (fd == -1) {
    perror("dup");
    abort();
  }

  w->pid_to_fd = realloc(w->pid_to_fd, len + diff);
  assert(w->pid_to_fd != NULL);

  w->pid_to_fd[len+0] = pid;
  w->pid_to_fd[len+1] = fd;
  w->pid_to_fd_len = len + diff;
}

int child_pid_to_fd_remove(wshd_t *w, pid_t pid) {
  int len = w->pid_to_fd_len;
  int diff = 2 * sizeof(int);
  int *cur;
  int offset;
  int fd = -1;

  for (cur = w->pid_to_fd; cur < (w->pid_to_fd + len); cur += diff) {
    if (cur[0] == pid) {
      fd = cur[1];
      offset = cur - w->pid_to_fd;

      if ((offset + diff) < len) {
        memmove(cur, cur + diff, len - offset - diff);
      }

      w->pid_to_fd = realloc(w->pid_to_fd, len - diff);
      w->pid_to_fd_len = len - diff;

      if (w->pid_to_fd_len) {
        assert(w->pid_to_fd != NULL);
      } else {
        assert(w->pid_to_fd == NULL);
      }

      break;
    }
  }

  return fd;
}

int child_fork(msg_request_t *req, int in, int out, int err) {
  int rv;

  rv = fork();
  if (rv == -1) {
    perror("fork");
    exit(1);
  }

  if (rv == 0) {
    char *default_argv[] = { "/bin/sh", NULL };
    char *default_envp[] = { NULL };
    char **argv = default_argv;
    char **envp = default_envp;

    rv = dup2(in, STDIN_FILENO);
    assert(rv != -1);

    rv = dup2(out, STDOUT_FILENO);
    assert(rv != -1);

    rv = dup2(err, STDERR_FILENO);
    assert(rv != -1);

    rv = setsid();
    assert(rv != -1);

    /* Set controlling terminal if needed */
    if (isatty(in)) {
      rv = ioctl(STDIN_FILENO, TIOCSCTTY, 1);
      assert(rv != -1);
    }

    /* Use argv from request if needed */
    if (req->arg.count) {
      argv = (char **)msg_array_export(&req->arg);
      assert(argv != NULL);
    }

    /* Use resource limits from request */
    rv = msg_rlimit_export(&req->rlim);
    if (rv == -1) {
      fprintf(stderr, "msg_rlimit_export: %s\n", strerror(errno));
      exit(255);
    }

    /* Set user from request */
    rv = msg_user_export(&req->user);
    if (rv == -1) {
      fprintf(stderr, "msg_user_export: %s\n", strerror(errno));
      exit(255);
    }

    execvpe(argv[0], argv, envp);
    perror("execvpe");
    exit(255);
  }

  return rv;
}

int child_handle_interactive(int fd, wshd_t *w, msg_request_t *req) {
  int i, j;
  int p[2][2];
  int p_[2];
  int rv;
  msg_response_t res;

  msg_response_init(&res);

  /* Initialize so that the error handler can do its job */
  for (i = 0; i < 2; i++) {
    p[i][0] = -1;
    p[i][1] = -1;
    p_[i] = -1;
  }

  rv = pipe(p[1]);
  if (rv == -1) {
    perror("pipe");
    abort();
  }

  fcntl_mix_cloexec(p[1][0]);
  fcntl_mix_cloexec(p[1][1]);

  rv = posix_openpt(O_RDWR | O_NOCTTY);
  if (rv < 0) {
    perror("posix_openpt");
    abort();
  }

  p[0][0] = rv;

  rv = grantpt(p[0][0]);
  if (rv < 0) {
    perror("grantpt");
    abort();
  }

  rv = unlockpt(p[0][0]);
  if (rv < 0) {
    perror("unlockpt");
    abort();
  }

  rv = open(ptsname(p[0][0]), O_RDWR);
  if (rv < 0) {
    perror("open");
    abort();
  }

  p[0][1] = rv;

  fcntl_mix_cloexec(p[0][0]);
  fcntl_mix_cloexec(p[0][1]);

  /* Descriptors to send to client */
  p_[0] = p[0][0];
  p_[1] = p[1][0];

  rv = un_send_fds(fd, (char *)&res, sizeof(res), p_, 2);
  if (rv == -1) {
    goto err;
  }

  rv = child_fork(req, p[0][1], p[0][1], p[0][1]);
  assert(rv > 0);

  child_pid_to_fd_add(w, rv, p[1][1]);

err:
  for (i = 0; i < 2; i++) {
    for (j = 0; j < 2; j++) {
      if (p[i][j] > -1) {
        close(p[i][j]);
        p[i][j] = -1;
      }
    }
  }

  if (fd > -1) {
    close(fd);
    fd = -1;
  }

  return 0;
}

int child_handle_noninteractive(int fd, wshd_t *w, msg_request_t *req) {
  int i, j;
  int p[4][2];
  int p_[4];
  int rv;
  msg_response_t res;

  msg_response_init(&res);

  /* Initialize so that the error handler can do its job */
  for (i = 0; i < 4; i++) {
    p[i][0] = -1;
    p[i][1] = -1;
    p_[i] = -1;
  }

  for (i = 0; i < 4; i++) {
    rv = pipe(p[i]);
    if (rv == -1) {
      perror("pipe");
      abort();
    }

    fcntl_mix_cloexec(p[i][0]);
    fcntl_mix_cloexec(p[i][1]);
  }

  /* Descriptors to send to client */
  p_[0] = p[0][1];
  p_[1] = p[1][0];
  p_[2] = p[2][0];
  p_[3] = p[3][0];

  rv = un_send_fds(fd, (char *)&res, sizeof(res), p_, 4);
  if (rv == -1) {
    goto err;
  }

  rv = child_fork(req, p[0][0], p[1][1], p[2][1]);
  assert(rv > 0);

  child_pid_to_fd_add(w, rv, p[3][1]);

err:
  for (i = 0; i < 4; i++) {
    for (j = 0; j < 2; j++) {
      if (p[i][j] > -1) {
        close(p[i][j]);
        p[i][j] = -1;
      }
    }
  }

  if (fd > -1) {
    close(fd);
    fd = -1;
  }

  return 0;
}

int child_accept(wshd_t *w) {
  int rv, fd;
  char buf[MSG_MAX_SIZE];
  size_t buflen = sizeof(buf);
  msg_request_t req;

  rv = accept(w->fd, NULL, NULL);
  if (rv == -1) {
    perror("accept");
    abort();
  }

  fd = rv;

  fcntl_mix_cloexec(fd);

  rv = un_recv_fds(fd, buf, buflen, NULL, 0);
  if (rv < 0) {
    perror("recvmsg");
    exit(255);
  }

  if (rv == 0) {
    close(fd);
    return 0;
  }

  assert(rv == sizeof(req));
  memcpy(&req, buf, sizeof(req));

  if (req.tty) {
    return child_handle_interactive(fd, w, &req);
  } else {
    return child_handle_noninteractive(fd, w, &req);
  }
}

void child_handle_sigchld(wshd_t *w) {
  pid_t pid;
  int status, exitstatus;
  int fd;

  while (1) {
    do {
      pid = waitpid(-1, &status, WNOHANG);
    } while (pid == -1 && errno == EINTR);

    /* Break when there are no more children */
    if (pid <= 0) {
      break;
    }

    /* Processes can be reparented, so a pid may not map to an fd */
    fd = child_pid_to_fd_remove(w, pid);
    if (fd == -1) {
      continue;
    }

    if (WIFEXITED(status)) {
      exitstatus = WEXITSTATUS(status);

      /* Send exit status to client */
      write(fd, &exitstatus, sizeof(exitstatus));
    } else {
      assert(WIFSIGNALED(status));

      /* No exit status */
    }

    close(fd);
  }
}

int child_signalfd(void) {
  sigset_t mask;
  int rv;
  int fd;

  sigemptyset(&mask);
  sigaddset(&mask, SIGCHLD);

  rv = sigprocmask(SIG_BLOCK, &mask, NULL);
  if (rv == -1) {
    perror("sigprocmask");
    abort();
  }

  fd = signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC);
  if (fd == -1) {
    perror("signalfd");
    abort();
  }

  return fd;
}

int child_loop(wshd_t *w) {
  int sfd;
  int rv;

  sfd = child_signalfd();

  for (;;) {
    fd_set fds;

    FD_ZERO(&fds);
    FD_SET(w->fd, &fds);
    FD_SET(sfd, &fds);

    do {
      rv = select(FD_SETSIZE, &fds, NULL, NULL, NULL);
    } while (rv == -1 && errno == EINTR);

    if (rv == -1) {
      perror("select");
      abort();
    }

    if (FD_ISSET(w->fd, &fds)) {
      child_accept(w);
    }

    if (FD_ISSET(sfd, &fds)) {
      struct signalfd_siginfo fdsi;

      rv = read(sfd, &fdsi, sizeof(fdsi));
      assert(rv == sizeof(fdsi));

      /* Ignore siginfo and loop waitpid to catch all children */
      child_handle_sigchld(w);
    }
  }

  return 1;
}

/* No header defines this */
extern int pivot_root(const char *new_root, const char *put_old);

int child_run(void *data) {
  wshd_t *w = (wshd_t *)data;
  int rv;
  char pivoted_lib_path[PATH_MAX];
  size_t pivoted_lib_path_len;

  /* Wait for parent */
  rv = barrier_wait(&w->barrier_parent);
  assert(rv == 0);

  rv = run(w->lib_path, "hook-child-before-pivot.sh");
  assert(rv == 0);

  /* Prepare lib path for pivot */
  strcpy(pivoted_lib_path, "/mnt");
  pivoted_lib_path_len = strlen(pivoted_lib_path);
  realpath(w->lib_path, pivoted_lib_path + pivoted_lib_path_len);

  rv = chdir(w->root_path);
  if (rv == -1) {
    perror("chdir");
    abort();
  }

  rv = mkdir("mnt", 0700);
  if (rv == -1 && errno != EEXIST) {
    perror("mkdir");
    abort();
  }

  rv = pivot_root(".", "mnt");
  if (rv == -1) {
    perror("pivot_root");
    abort();
  }

  rv = chdir("/");
  if (rv == -1) {
    perror("chdir");
    abort();
  }

  rv = run(pivoted_lib_path, "hook-child-after-pivot.sh");
  assert(rv == 0);

  rv = mount_umount_pivoted_root("/mnt");
  if (rv == -1) {
    exit(1);
  }

  /* Signal parent */
  rv = barrier_signal(&w->barrier_child);
  assert(rv == 0);

  return child_loop(w);
}

pid_t child_start(wshd_t *w) {
  long pagesize;
  void *stack;
  int flags = 0;
  pid_t pid;

  pagesize = sysconf(_SC_PAGESIZE);
  stack = alloca(pagesize);
  assert(stack != NULL);

  /* Point to top of stack (it grows down) */
  stack = stack + pagesize;

  /* Setup namespaces */
  flags |= CLONE_NEWIPC;
  flags |= CLONE_NEWNET;
  flags |= CLONE_NEWNS;
  flags |= CLONE_NEWPID;
  flags |= CLONE_NEWUTS;

  pid = clone(child_run, stack, flags, w);
  if (pid == -1) {
    perror("clone");
    abort();
  }

  return pid;
}

void parent_setenv_pid(wshd_t *w, int pid) {
  char buf[16];
  int rv;

  rv = snprintf(buf, sizeof(buf), "%d", pid);
  assert(rv < sizeof(buf));

  rv = setenv("PID", buf, 1);
  assert(rv == 0);
}

int parent_run(wshd_t *w) {
  char path[MAXPATHLEN];
  int rv;
  pid_t pid;

  memset(path, 0, sizeof(path));

  strcpy(path + strlen(path), w->run_path);
  strcpy(path + strlen(path), "/");
  strcpy(path + strlen(path), "wshd.sock");

  w->fd = un_listen(path);

  rv = barrier_open(&w->barrier_parent);
  assert(rv == 0);

  rv = barrier_open(&w->barrier_child);
  assert(rv == 0);

  /* Unshare mount namespace, so the before clone hook is free to mount
   * whatever it needs without polluting the global mount namespace. */
  rv = unshare(CLONE_NEWNS);
  assert(rv == 0);

  rv = run(w->lib_path, "hook-parent-before-clone.sh");
  assert(rv == 0);

  pid = child_start(w);
  assert(pid > 0);

  parent_setenv_pid(w, pid);

  rv = run(w->lib_path, "hook-parent-after-clone.sh");
  assert(rv == 0);

  rv = barrier_signal(&w->barrier_parent);
  if (rv == -1) {
    fprintf(stderr, "Error waking up child process\n");
    exit(1);
  }

  rv = barrier_wait(&w->barrier_child);
  if (rv == -1) {
    fprintf(stderr, "Error waiting for acknowledgement from child process\n");
    exit(1);
  }

  return 0;
}

int main(int argc, char **argv) {
  wshd_t *w;
  int rv;

  w = calloc(1, sizeof(*w));
  assert(w != NULL);

  w->argc = argc;
  w->argv = argv;

  rv = wshd__getopt(w);
  if (rv == -1) {
    exit(1);
  }

  if (w->run_path == NULL) {
    w->run_path = "run";
  }

  if (w->lib_path == NULL) {
    w->lib_path = "lib";
  }

  if (w->root_path == NULL) {
    w->root_path = "root";
  }

  if (w->title != NULL) {
    setproctitle(argv, w->title);
  }

  assert_directory(w->run_path);
  assert_directory(w->lib_path);
  assert_directory(w->root_path);

  parent_run(w);

  return 0;
}
