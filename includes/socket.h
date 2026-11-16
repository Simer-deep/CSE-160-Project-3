#ifndef __SOCKET_H__
#define __SOCKET_H__

enum {
    MAX_NUM_OF_SOCKETS = 3,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
    TRANSPORT_SEND_WINDOW = 48,
    TRANSPORT_MAX_RETRIES = 8,
    TRANSPORT_RTO_MS = 2000,
    TRANSPORT_TIME_WAIT_MS = 10000
};

enum socket_state {
    CLOSED,
    LISTEN,
    SYN_SENT,
    SYN_RCVD,
    ESTABLISHED,
    FIN_WAIT_1,
    FIN_WAIT_2,
    CLOSE_WAIT,
    LAST_ACK,
    CLOSING,
    TIME_WAIT
};

typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

typedef nx_struct socket_addr_t {
    nx_socket_port_t port;
    nx_uint16_t addr;
} socket_addr_t;

typedef uint8_t socket_t;

typedef struct socket_store_t {

    bool inUse;
    enum socket_state state;

    uint16_t localAddr;
    socket_port_t localPort;

    uint16_t remoteAddr;
    socket_port_t remotePort;

    uint16_t iss;
    uint16_t irs;
    uint16_t finSeq;

    bool closeRequested;
    bool finSent;
    bool finAcked;
    bool finReceived;

    uint8_t controlRetries;
    uint32_t controlDeadline;
    uint32_t timeWaitDeadline;

    uint8_t sendBuff[SOCKET_BUFFER_SIZE];

    uint16_t sndUna;
    uint16_t sndNxt;
    uint16_t sndEnd;

    uint8_t sendHead;
    uint8_t sendUsed;

    uint8_t peerWnd;
    uint8_t sendWindow;

    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];

    uint16_t rcvNxt;

    uint8_t recvHead;
    uint8_t recvUsed;

    uint32_t dataDeadline;
    uint8_t dataRetries;

} socket_store_t;

#endif