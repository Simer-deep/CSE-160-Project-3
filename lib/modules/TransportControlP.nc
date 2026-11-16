#include "../../includes/socket.h"
#include "../../includes/transport.h"
#include "../../includes/packet.h"
#include <string.h>

module TransportControlP {
    provides interface Transport;

    uses interface TransportStream;
}

implementation {

    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    socket_t allocateSocket() {
        uint8_t i;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (!sockets[i].inUse) {
                memset(&sockets[i], 0, sizeof(socket_store_t));

                sockets[i].inUse = TRUE;
                sockets[i].state = CLOSED;
                sockets[i].localAddr = TOS_NODE_ID;
                sockets[i].sendWindow = TRANSPORT_SEND_WINDOW;
                sockets[i].peerWindow = 0;

                return i + 1;
            }
        }

        return 0;
    }

    socket_store_t* getSocket(socket_t fd) {
        if (fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return NULL;
        }

        if (!sockets[fd - 1].inUse) {
            return NULL;
        }

        return &sockets[fd - 1];
    }

    socket_t findConnection(
        uint16_t localAddr,
        uint8_t localPort,
        uint16_t remoteAddr,
        uint8_t remotePort
    ) {
        uint8_t i;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            socket_store_t* conn = &sockets[i];

            if (!conn->inUse || conn->state == LISTEN) {
                continue;
            }

            if (conn->localAddr == localAddr &&
                conn->localPort == localPort &&
                conn->remoteAddr == remoteAddr &&
                conn->remotePort == remotePort) {
                return i + 1;
            }
        }

        return 0;
    }

    socket_t findListener(uint8_t port) {
        uint8_t i;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].inUse &&
                sockets[i].state == LISTEN &&
                sockets[i].localAddr == TOS_NODE_ID &&
                sockets[i].localPort == port) {
                return i + 1;
            }
        }

        return 0;
    }

    command socket_t Transport.socket() {
        return allocateSocket();
    }

    command error_t Transport.bind(
        socket_t fd,
        socket_addr_t* addr
    ) {
        socket_store_t* conn = getSocket(fd);

        if (conn == NULL || addr == NULL) {
            return FAIL;
        }

        if (conn->state != CLOSED) {
            return FAIL;
        }

        if (addr->addr != TOS_NODE_ID) {
            return FAIL;
        }

        conn->localAddr = addr->addr;
        conn->localPort = addr->port;

        return SUCCESS;
    }

    command error_t Transport.listen(socket_t fd) {
        socket_store_t* conn = getSocket(fd);

        if (conn == NULL || conn->state != CLOSED) {
            return FAIL;
        }

        if (conn->localPort == 0) {
            return FAIL;
        }

        if (findListener(conn->localPort) != 0) {
            return FAIL;
        }

        conn->state = LISTEN;
        return SUCCESS;
    }

    command socket_t Transport.accept(socket_t fd) {
        return 0;
    }

    command error_t Transport.connect(
        socket_t fd,
        socket_addr_t* addr
    ) {
        return FAIL;
    }

    command uint16_t Transport.write(
        socket_t fd,
        uint8_t* buff,
        uint16_t bufflen
    ) {
        return 0;
    }

    command uint16_t Transport.read(
        socket_t fd,
        uint8_t* buff,
        uint16_t bufflen
    ) {
        return 0;
    }

    command error_t Transport.receive(pack* package) {
        return FAIL;
    }

    command error_t Transport.close(socket_t fd) {
        return FAIL;
    }

    command error_t Transport.release(socket_t fd) {
        socket_store_t* conn = getSocket(fd);

        if (conn == NULL || conn->state != CLOSED) {
            return FAIL;
        }

        memset(conn, 0, sizeof(socket_store_t));
        return SUCCESS;
    }

    event error_t TransportStream.sendSegment(
        socket_store_t* conn,
        uint8_t flags,
        uint16_t seq,
        uint16_t ack,
        uint8_t window,
        uint8_t* data,
        uint8_t length
    ) {
        return FAIL;
    }
}