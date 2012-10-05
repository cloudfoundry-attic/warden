#define _GNU_SOURCE

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "msg.h"

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

void msg_request_init(msg_request_t *req) {
  memset(req, 0, sizeof(*req));
  req->version = MSG_VERSION;
}

void msg_response_init(msg_response_t *res) {
  memset(res, 0, sizeof(*res));
  res->version = MSG_VERSION;
}
