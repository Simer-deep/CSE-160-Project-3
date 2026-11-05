#ifndef DV_H
#define DV_H

#include "packet.h"

enum {
    DV_INFINITY = 16,
    DV_ENTRY_SIZE = 2,
    DV_PACKET_HEADER_SIZE = 3,

    DV_ROUTE_TIMEOUT = 20000,
    DV_WITHDRAW_TIMEOUT = 30000,
    DV_REASSEMBLY_TIMEOUT = 10000,

    DV_MAX_ENTRIES =
        (PACKET_MAX_PAYLOAD_SIZE - DV_PACKET_HEADER_SIZE) / DV_ENTRY_SIZE,

    DV_MAX_ROUTES = 32,
    DV_MAX_NEIGHBORS = 15,

    DV_MAX_PACKETS =
        (DV_MAX_ROUTES + DV_MAX_ENTRIES - 1) / DV_MAX_ENTRIES,

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
