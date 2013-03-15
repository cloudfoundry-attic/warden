#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pwd.h"

#define _GETPWNAM_NEXT(x, y)                  \
  do {                                        \
      if ((y) != NULL) {                      \
        (x) = (y) + 1;                        \
      }                                       \
                                              \
      (y) = strchr((x), ':');                 \
                                              \
      /* Search for \n in last iteration */   \
      if ((y) == NULL) {                      \
        (y) = strchr((x), '\n');              \
      }                                       \
                                              \
      if ((y) == NULL) {                      \
        goto done;                            \
      }                                       \
                                              \
      *(y) = '\0';                            \
  } while(0);

/* Instead of using getpwnam from glibc, the following custom version is used
 * because we need to bypass dynamically loading the nsswitch libraries.
 * The version of glibc inside a container may be different than the version
 * that wshd is compiled for, leading to undefined behavior. */
struct passwd *getpwnam(const char *name) {
  static struct passwd passwd;
  static char buf[1024];
  struct passwd *_passwd = NULL;
  FILE *f;
  char *p, *q;

  f = fopen("/etc/passwd", "r");
  if (f == NULL) {
    goto done;
  }

  while (fgets(buf, sizeof(buf), f) != NULL) {
    p = buf;
    q = NULL;

    /* Username */
    _GETPWNAM_NEXT(p, q);

    if (strcmp(p, name) != 0) {
      continue;
    }

    passwd.pw_name = p;

    /* User password */
    _GETPWNAM_NEXT(p, q);
    passwd.pw_passwd = p;

    /* User ID */
    _GETPWNAM_NEXT(p, q);
    passwd.pw_uid = atoi(p);

    /* Group ID */
    _GETPWNAM_NEXT(p, q);
    passwd.pw_gid = atoi(p);

    /* User information */
    _GETPWNAM_NEXT(p, q);
    passwd.pw_gecos = p;

    /* Home directory */
    _GETPWNAM_NEXT(p, q);
    passwd.pw_dir = p;

    /* Shell program */
    _GETPWNAM_NEXT(p, q);
    passwd.pw_shell = p;

    /* Done! */
    _passwd = &passwd;
    goto done;
  }

done:
  if (f != NULL) {
    fclose(f);
  }

  return _passwd;
}

#undef _GETPWNAM_NEXT
