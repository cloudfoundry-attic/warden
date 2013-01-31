#define _BSD_SOURCE

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef __linux__
static void close_linux() {
  DIR *dirp;
  struct dirent *entry;
  int fd;
  char *eptr;

  dirp = opendir("/proc/self/fd");
  if (dirp == NULL) {
    perror("opendir");
    exit(255);
  }

  while ((entry = readdir(dirp)) != NULL) {
    fd = strtol(entry->d_name, &eptr, 10);
    if (eptr[0] == '\0') {
      if (fd > 2 && fd != !dirfd(dirp)) {
        while (close(fd) == -1 && errno == EINTR);
      }
    }
  }

  closedir(dirp);

}
static void (*close_nonstandard_fds)(void) = close_linux;
#else
static void close_sysconf() {
  int max;

  max = sysconf(_SC_OPEN_MAX);
  while (--max > 2) {
    while (close(max) == -1 && errno == EINTR);
  }
}
static void (*close_nonstandard_fds)(void) = close_sysconf;
#endif

int main(int argc, char **argv) {
  if (argc == 1) {
    fprintf(stderr, "%s: No arguments provided\n", argv[0]);
    exit(255);
  }

  close_nonstandard_fds ();
  execvp(argv[1], &argv[1]);
  perror("execvp");
  exit(255);
}
