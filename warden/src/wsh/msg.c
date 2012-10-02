#define _GNU_SOURCE

#include <string.h>

#include "msg.h"

void msg_request_init(msg_request_t *req) {
  memset(req, 0, sizeof(*req));
  req->version = MSG_VERSION;
}

void msg_response_init(msg_response_t *res) {
  memset(res, 0, sizeof(*res));
  res->version = MSG_VERSION;
}
