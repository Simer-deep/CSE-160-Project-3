#ifndef __TRANSPORT_H__
#define __TRANSPORT_H__

#include "packet.h"
#include "socket.h"

enum {
    TCP_FLAG_SYN  = 0x01,
    TCP_FLAG_ACK  = 0x02,
    TCP_FLAG_FIN  = 0x04,
    TCP_FLAG_DATA = 0x08
};

enum {
    TRANSPORT_HEADER_SIZE = 9,
    TRANSPORT_MAX_DATA_SIZE =
        PACKET_MAX_PAYLOAD_SIZE - TRANSPORT_HEADER_SIZE
};

typedef nx_struct transport_header_t {
    nx_uint8_t srcPort;
    nx_uint8_t destPort;
    nx_uint8_t flags;
    nx_uint16_t seq;
    nx_uint16_t ack;
    nx_uint8_t window;
    nx_uint8_t length;
} transport_header_t;

#endif