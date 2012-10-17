#define _BSD_SOURCE

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/*
 * The code in this file is not portable.
 *
 * Search for implementations of closefrom(2) for a portable version.
 */

int main(int argc, char **argv) {
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

  execvp(argv[1], &argv[1]);
  perror("execvp");
  exit(255);
}
