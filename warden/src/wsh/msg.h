#ifndef MSG_H
#define MSG_H 1

#define MSG_VERSION 1

typedef struct msg_request_s msg_request_t;
typedef struct msg_response_s msg_response_t;

struct msg_request_s {
  int version;

  int tty;
};

struct msg_response_s {
  int version;

  int err;
};

void msg_request_init(msg_request_t *req);
void msg_response_init(msg_response_t *res);

#endif
