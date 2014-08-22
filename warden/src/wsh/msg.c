#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "msg.h"
#include "pwd.h"

int msg_array_import(msg__array_t * a, int count, const char ** ptr) {
  size_t off = 0;
  size_t len = 0;
  int i;

  a->count = count;
  memset(a->buf, 0, sizeof(a->buf));

  for (i = 0; i < count; i++) {
    len = strlen(ptr[i]);

    if ((sizeof(a->buf) - off) < (len + 1)) {
      return -1;
    }

    memcpy(a->buf + off, ptr[i], len);
    off += len + 1;
  }

  return 0;
}

const char ** msg_array_export(msg__array_t * a) {
  const char ** ptr;
  size_t off = 0;
  size_t len = 0;
  int i;

  ptr = malloc(sizeof(const char *) * (a->count + 1));
  assert(ptr != NULL);

  for (i = 0; i < a->count; i++) {
    ptr[i] = &a->buf[off];
    len = strlen(ptr[i]);
    off += len + 1;
  }

  ptr[i] = NULL;

  return ptr;
}

#define _R(X, Y, Z) { X, #X, { Y, Z } }

static struct {
  int id;
  const char* name;
  struct rlimit rlim;
} rlimits[] = {
  _R(RLIMIT_AS, RLIM_INFINITY, RLIM_INFINITY),
  _R(RLIMIT_CORE, 0, 0),
  _R(RLIMIT_CPU, RLIM_INFINITY, RLIM_INFINITY),
  _R(RLIMIT_DATA, RLIM_INFINITY, RLIM_INFINITY),
  _R(RLIMIT_FSIZE, RLIM_INFINITY, RLIM_INFINITY),
  _R(RLIMIT_LOCKS, RLIM_INFINITY, RLIM_INFINITY),
  _R(RLIMIT_MEMLOCK, 65536, 65536),
  _R(RLIMIT_MSGQUEUE, 819200, 819200),
  _R(RLIMIT_NICE, 0, 0),
  _R(RLIMIT_NOFILE, 1024, 1024),
  _R(RLIMIT_NPROC, 1024, 1024),
  _R(RLIMIT_RSS, RLIM_INFINITY, RLIM_INFINITY),
  _R(RLIMIT_RTPRIO, 0, 0),
  _R(RLIMIT_SIGPENDING, 1024, 1024),
  _R(RLIMIT_STACK, 8192 * 1024, 8192 * 1024),
};

#undef _R

int msg_rlimit_import(msg__rlimit_t *r) {
  int i;
  struct rlimit rlim;
  char *value;
  int rv;

  r->count = 0;
  memset(r->rlim, 0, sizeof(r->rlim));

  for (i = 0; i < (sizeof(rlimits)/sizeof(rlimits[0])); i++) {
    rlim = rlimits[i].rlim;
    value = getenv(rlimits[i].name);
    if (value != NULL) {
      rv = sscanf(value, "%ld %ld", &rlim.rlim_cur, &rlim.rlim_max);
      if (rv > 0) {
        if (rv == 1) {
          rlim.rlim_max = rlim.rlim_cur;
        }
      } else {
        errno = EINVAL;
        return -1;
      }
    }

    r->rlim[r->count].id = rlimits[i].id;
    r->rlim[r->count].rlim = rlim;
    r->count++;
  }

  return 0;
}

int msg_rlimit_export(msg__rlimit_t *r) {
  int i;
  int rv;

  for (i = 0; i < r->count; i++) {
    rv = setrlimit(r->rlim[i].id, &r->rlim[i].rlim);
    if (rv == -1) {
      fprintf(stderr, "%d\n", r->rlim[i].id);
      return rv;
    }
  }

  return 0;
}

int msg_user_import(msg__user_t *u, const char *name) {
  int rv;

  if (name != NULL) {
    rv = snprintf(u->name, sizeof(u->name), "%s", name);
    assert(rv < sizeof(u->name));
  }

  return 0;
}

int msg_user_export(msg__user_t *u, struct passwd *pw) {
  ((void) u);

  int rv;

  rv = setgid(pw->pw_gid);
  if (rv == -1) {
    return rv;
  }

  rv = setuid(pw->pw_uid);
  if (rv == -1) {
    return rv;
  }

  return 0;
}

int msg_lang_import(msg__lang_t *l) {
  int rv;

  char *lang = getenv("LANG");
  if (lang != NULL) {
    rv = snprintf(l->lang, sizeof(l->lang), "%s", lang);
    assert(rv < sizeof(l->lang));
  }

  return 0;
}

int msg_lang_export(msg__lang_t *l, msg__lang_t *lang) {
  int rv;

  lang->lang[0] = '\0';

  if (l != NULL) {
    if (strnlen(l->lang, sizeof(l->lang)) >= sizeof(l->lang)) {
      errno = EINVAL;
      rv = -1;
    } else {
      memcpy(lang, l, sizeof(*lang));
      rv = 0;
    }
  }

  return rv;
}

void msg_request_init(msg_request_t *req) {
  assert(sizeof(msg_request_t) <= MSG_MAX_SIZE);
  memset(req, 0, sizeof(*req));
  req->version = MSG_VERSION;
}

void msg_response_init(msg_response_t *res) {
  assert(sizeof(msg_response_t) <= MSG_MAX_SIZE);
  memset(res, 0, sizeof(*res));
  res->version = MSG_VERSION;
}
