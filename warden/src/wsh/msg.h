#ifndef MSG_H
#define MSG_H 1

#define MSG_VERSION 1
#define MSG_MAX_SIZE (16 * 1024)

typedef struct msg__array_s msg__array_t;
typedef struct msg_request_s msg_request_t;
typedef struct msg_response_s msg_response_t;

struct msg__array_s {
  int count;
  char buf[8 * 1024];
};

struct msg_request_s {
  int version;
  int tty;
  msg__array_t arg;
};

struct msg_response_s {
  int version;
};

int msg_array_import(msg__array_t * a, int count, const char ** ptr);
const char ** msg_array_export(msg__array_t * a);

void msg_request_init(msg_request_t *req);
void msg_response_init(msg_response_t *res);

#endif
