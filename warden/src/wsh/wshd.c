#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "barrier.h"
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

  /* File descriptor of listening socket */
  int fd;

  barrier_t barrier_parent;
  barrier_t barrier_child;
  pid_t pid;
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

  return 0;
}

int wshd__getopt(wshd_t *w) {
  int i = 1;
  int j = w->argc - i;

  while (i < w->argc) {
    if (j >= 2) {
      if (strcmp("--run", w->argv[i]) == 0) {
        w->run_path = w->argv[i+1];
      } else if (strcmp("--lib", w->argv[i]) == 0) {
        w->lib_path = w->argv[i+1];
      } else if (strcmp("--root", w->argv[i]) == 0) {
        w->root_path = w->argv[i+1];
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

int child_accept(wshd_t *w) {
  int fd = -1;
  int i, j;
  int rv;
  int p[3][2];
  int p_[3];
  int data = 0;

  for (i = 0; i < 3; i++) {
    p[i][0] = -1;
    p[i][1] = -1;
    p_[i] = -1;
  }

  fd = accept(w->fd, NULL, NULL);
  if (fd == -1) {
    perror("accept");
    abort();
  }

  for (i = 0; i < 3; i++) {
    rv = pipe(p[i]);
    if (rv == -1) {
      perror("pipe");
      abort();
    }
  }

  p_[0] = p[0][1];
  p_[1] = p[1][0];
  p_[2] = p[2][0];

  rv = un_send_fds(fd, (char *)&data, sizeof(data), p_, 3);
  if (rv == -1) {
    goto err;
  }

  /* Run /bin/sh with these fds */
  rv = fork();
  if (rv == -1) {
    perror("fork");
    exit(1);
  }

  if (rv == 0) {
    /* Close remote fds */
    close(p[0][1]);
    close(p[1][0]);
    close(p[2][0]);

    /* Dup local fds */
    rv = dup2(p[0][0], STDIN_FILENO);
    if (rv == -1) {
      perror("dup2");
      abort();
    }

    rv = dup2(p[1][1], STDOUT_FILENO);
    if (rv == -1) {
      perror("dup2");
      abort();
    }

    rv = dup2(p[2][1], STDERR_FILENO);
    if (rv == -1) {
      perror("dup2");
      abort();
    }

    /* Close dup sources */
    close(p[0][0]);
    close(p[1][1]);
    close(p[2][1]);

    char * const argv[] = { "/bin/sh", NULL };
    execvp(argv[0], argv);
    perror("execvp");
    abort();
  }

err:
  for (i = 0; i < 3; i++) {
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

int child_loop(wshd_t *w) {
  fd_set fds;
  int rv;

  for (;;) {
    FD_ZERO(&fds);
    FD_SET(w->fd, &fds);

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

  assert_directory(w->run_path);
  assert_directory(w->lib_path);
  assert_directory(w->root_path);

  parent_run(w);

  return 0;
}
