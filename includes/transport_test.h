#ifndef TRANSPORT_TEST_H
#define TRANSPORT_TEST_H

#include "socket.h"

enum {
    TRANSPORT_TEST_CHUNK_SIZE = 32,
    TRANSPORT_TEST_INTERVAL_MS = 50
};

typedef struct transport_test_stats_t {
    uint32_t accepted;
    uint32_t acknowledged;
    uint32_t consumed;
    uint32_t mismatches;
    bool producerDone;
    bool consumerDone;
    bool paused;
    bool failed;
} transport_test_stats_t;

#endif
