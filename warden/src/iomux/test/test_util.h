#ifndef TEST_H
#define TEST_H 1

#include <stdio.h>

#define TEST_CHECK(p) do {                                         \
    printf("%s - %s %s:%d\n",                                      \
           (p) ? "PASS" : "FAIL",                                  \
           #p,                                                     \
           __FILE__, __LINE__);                                    \
  } while (0)

#endif
