#include "../../includes/socket.h"
#include "../../includes/transport.h"
#include "../../includes/packet.h"
#include <string.h>

module TransportControlP {
    provides interface Transport;

    uses interface TransportStream;
    uses interface IPRouting;
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
        uint8_t srcPort;
        uint8_t destPort;
        uint8_t flags;
        uint16_t seq;
        uint16_t ack;
        uint8_t window;
        uint8_t length;

        socket_t fd;
        socket_store_t* conn;
        error_t result = SUCCESS;

        if (package == NULL ||
            package->protocol != PROTOCOL_TCP ||
            package->dest != TOS_NODE_ID) {
            return FAIL;
        }

        srcPort = package->payload[0];
        destPort = package->payload[1];
        flags = package->payload[2];

        seq = ((uint16_t)package->payload[3] << 8) |
              package->payload[4];

        ack = ((uint16_t)package->payload[5] << 8) |
              package->payload[6];

        window = package->payload[7];
        length = package->payload[8];

        if (srcPort == 0 || destPort == 0 ||
            length > TRANSPORT_MAX_DATA_SIZE ||
            window > SOCKET_BUFFER_SIZE ||
            (flags & ~(TCP_FLAG_SYN | TCP_FLAG_ACK |
                       TCP_FLAG_FIN | TCP_FLAG_DATA)) != 0) {
            return FAIL;
        }

        if (length > 0 && !(flags & TCP_FLAG_DATA)) {
            return FAIL;
        }

        if ((flags & TCP_FLAG_DATA) && length == 0) {
            return FAIL;
        }

        fd = findConnection(
            TOS_NODE_ID,
            destPort,
            package->src,
            srcPort
        );

        if (fd == 0) {
            dbg(TRANSPORT_CHANNEL,
                "Node %d: No TCP connection for %d:%d\n",
                TOS_NODE_ID, package->src, srcPort);
            return FAIL;
        }

        conn = getSocket(fd);

        if (conn == NULL) {
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL,
            "Node %d TCP receive: fd=%d flags=%d seq=%d ack=%d len=%d\n",
            TOS_NODE_ID, fd, flags, seq, ack, length);

        if (flags & (TCP_FLAG_SYN | TCP_FLAG_FIN)) {
            return FAIL;
        }

        if (flags & TCP_FLAG_ACK) {
            result = call TransportStream.onAck(
                conn, ack, window
            );
        }

        if (flags & TCP_FLAG_DATA) {
            result = call TransportStream.onData(
                conn,
                seq,
                (uint8_t*)&package->payload[TRANSPORT_HEADER_SIZE],
                length
            );
        }

        if (!(flags & (TCP_FLAG_ACK | TCP_FLAG_DATA))) {
            return FAIL;
        }

        return result;
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
        uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
        uint8_t i;

        if (conn == NULL || !conn->inUse) {
            return FAIL;
        }

        if (length > TRANSPORT_MAX_DATA_SIZE) {
            return FAIL;
        }

        if (length > 0 && data == NULL) {
            return FAIL;
        }

        if (conn->remoteAddr == 0 ||
            conn->remotePort == 0 ||
            conn->localPort == 0) {
            return FAIL;
        }

        memset(payload, 0, sizeof(payload));

        payload[0] = conn->localPort;
        payload[1] = conn->remotePort;
        payload[2] = flags;

        payload[3] = (uint8_t)(seq >> 8);
        payload[4] = (uint8_t)(seq & 0xFF);

        payload[5] = (uint8_t)(ack >> 8);
        payload[6] = (uint8_t)(ack & 0xFF);

        payload[7] = window;
        payload[8] = length;

        for (i = 0; i < length; i++) {
            payload[TRANSPORT_HEADER_SIZE + i] = data[i];
        }

        return call IPRouting.sendTransport(
            conn->remoteAddr,
            payload,
            TRANSPORT_HEADER_SIZE + length
        );
    }

    event void IPRouting.transportReceived(pack* packet) 
    {

    }
}