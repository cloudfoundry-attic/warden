#ifndef PWD_H
#define PWD_H

#include <stdint.h>

#define getpwnam __wshd_getpwnam

struct passwd {
  char *pw_name;   /* Username. */
  char *pw_passwd; /* Password. */
  uint16_t pw_uid; /* User ID. */
  uint16_t pw_gid; /* Group ID. */
  char *pw_gecos;  /* Real name. */
  char *pw_dir;    /* Home directory. */
  char *pw_shell;  /* Shell program. */
};

struct passwd *getpwnam(const char *name);

#endif
