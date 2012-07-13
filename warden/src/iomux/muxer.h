#ifndef MUXER_H
#define MUXER_H 1

#include <stddef.h>

typedef struct muxer_s muxer_t;

/**
 * Allocates a new muxer
 *
 * @param accept_fd      FD to listen on for new connections
 * @param source_fd      The input fd.
 * @param ring_buf_size  How much data should be buffered.
 *
 * @return A pointer to the new muxer
 */
muxer_t *muxer_alloc(int accept_fd, int source_fd, size_t ring_buf_size);

void muxer_run(muxer_t *muxer);

void muxer_wait_for_client(muxer_t *muxer);

void muxer_stop(muxer_t *muxer);

void muxer_free(muxer_t *muxer);

#endif
