#ifndef LOG_H
#define LOG_H 1

#ifdef DEBUG

void _dlog(const char *file, const char *func, int line,
           const char *format, ...);

#define DLOG(format, ...) _dlog(__FILE__, __FUNCTION__, __LINE__, (format), ##__VA_ARGS__)

#else

#define DLOG(format, ...)

#endif

#endif
