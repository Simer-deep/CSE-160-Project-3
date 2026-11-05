#ifndef DV_H
#define DV_H

#include "packet.h"

enum {
    DV_INFINITY = 16,
    DV_ENTRY_SIZE = 2,
    DV_ROUTE_TIMEOUT = 20000,
    DV_WITHDRAW_TIMEOUT = 30000,

    DV_MAX_ENTRIES =
        (PACKET_MAX_PAYLOAD_SIZE - 1) / DV_ENTRY_SIZE,

    DV_MAX_ROUTES = 32,
    DV_NO_NEXT_HOP = 0xFFFF
};

enum {
    DV_ROUTE_UNUSED = 0,
    DV_ROUTE_VALID = 1,
    DV_ROUTE_WITHDRAWN = 2
};

typedef struct dv_route {
    uint16_t destination;
    uint16_t nextHop;
    uint8_t cost;
    uint8_t state;
    uint32_t lastUpdated;
} dv_route_t;

#endif
