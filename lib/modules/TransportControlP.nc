#include "../../includes/socket.h"
#include "../../includes/transport.h"
#include "../../includes/packet.h"
#include <string.h>
#include <Timer.h>

module TransportControlP {
    provides interface Transport;

    uses interface TransportStream;
    uses interface IPRouting;

    uses interface Timer<TMilli> as ControlTimer;
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

    error_t sendControlPacket(
        socket_store_t* conn,
        uint8_t flags,
        uint16_t seq,
        uint16_t ack
    ) {
        uint8_t payload[TRANSPORT_HEADER_SIZE];
        uint8_t window;

        if (conn == NULL || !conn->inUse ||
            conn->localPort == 0 ||
            conn->remotePort == 0 ||
            conn->remoteAddr == 0) {
            return FAIL;
        }

        window = SOCKET_BUFFER_SIZE - conn->receiveUsed;

        payload[0] = conn->localPort;
        payload[1] = conn->remotePort;
        payload[2] = flags;

        payload[3] = (uint8_t)(seq >> 8);
        payload[4] = (uint8_t)(seq & 0xFF);

        payload[5] = (uint8_t)(ack >> 8);
        payload[6] = (uint8_t)(ack & 0xFF);

        payload[7] = window;
        payload[8] = 0;

        return call IPRouting.sendTransport(
            conn->remoteAddr,
            payload,
            TRANSPORT_HEADER_SIZE
        );
    }

    command error_t Transport.connect(
        socket_t fd,
        socket_addr_t* addr
    ) {
        socket_store_t* conn = getSocket(fd);
        uint16_t initialSeq;

        if (conn == NULL || addr == NULL) {
            return FAIL;
        }

        if (conn->state != CLOSED || conn->localPort == 0) {
            return FAIL;
        }

        if (addr->addr == 0 || addr->port == 0 ||
            addr->addr == TOS_NODE_ID) {
            return FAIL;
        }

        conn->remoteAddr = addr->addr;
        conn->remotePort = addr->port;

        initialSeq = (uint16_t)(
            TOS_NODE_ID * 100 + fd * 10
        );

        conn->initialSendSequence = initialSeq;
        conn->initialReceiveSequence = 0;

        conn->controlRetries = 0;
        conn->controlDeadline = 0;

        conn->state = SYN_SENT;

        if (sendControlPacket(
                conn,
                TCP_FLAG_SYN,
                initialSeq,
                0
            ) != SUCCESS) {

            conn->state = CLOSED;
            conn->remoteAddr = 0;
            conn->remotePort = 0;

            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL,
            "Node %d sent SYN to %d:%d seq=%d\n",
            TOS_NODE_ID,
            conn->remoteAddr,
            conn->remotePort,
            initialSeq);
        
        conn->controlDeadline = call ControlTimer.getNow() + TRANSPORT_RTO_MS;

        if (conn->controlDeadline == 0) 
        {
            conn->controlDeadline = 1;
        }

        if (!call ControlTimer.isRunning()) 
        {
            call ControlTimer.startPeriodic(250);
        }

        return SUCCESS;
    }

    command uint16_t Transport.write(
        socket_t fd,
        uint8_t* buff,
        uint16_t bufflen
    ) {
        socket_store_t* conn = getSocket(fd);

        if (conn == NULL || buff == NULL ||
            conn->state != ESTABLISHED ||
            bufflen == 0) {
            return 0;
        }

        return call TransportStream.write(
            conn,
            buff,
            bufflen
        );
    }
    
    command uint16_t Transport.read(
        socket_t fd,
        uint8_t* buff,
        uint16_t bufflen
    ) {
        socket_store_t* conn = getSocket(fd);

        if (conn == NULL || buff == NULL ||
            bufflen == 0) {
            return 0;
        }

        if (conn->state == CLOSED ||
            conn->state == LISTEN ||
            conn->state == SYN_SENT ||
            conn->state == SYN_RCVD) {
            return 0;
        }

        return call TransportStream.read(
            conn,
            buff,
            bufflen
        );
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

        if (flags == TCP_FLAG_SYN) 
        {
            socket_t listenFd;
            socket_t existingFd;
            socket_t newFd;
            socket_store_t* newConn;
            socket_store_t* existingConn;
            uint16_t initialSeq;

            existingFd = findConnection(
                TOS_NODE_ID,
                destPort,
                package->src,
                srcPort
            );

            if (existingFd != 0) {
                existingConn = getSocket(existingFd);

                if (existingConn != NULL &&
                    existingConn->state == SYN_RCVD &&
                    seq == existingConn->initialReceiveSequence) {

                    return sendControlPacket(
                        existingConn,
                        TCP_FLAG_SYN | TCP_FLAG_ACK,
                        existingConn->initialSendSequence,
                        (uint16_t)(seq + 1)
                    );
                }

                return FAIL;
            }

            listenFd = findListener(destPort);

            if (listenFd == 0) {
                dbg(TRANSPORT_CHANNEL,
                    "Node %d: No listener on port %d\n",
                    TOS_NODE_ID, destPort);
                return FAIL;
            }

            newFd = allocateSocket();

            if (newFd == 0) {
                dbg(TRANSPORT_CHANNEL,
                    "Node %d: No free TCP sockets\n",
                    TOS_NODE_ID);
                return FAIL;
            }

            newConn = getSocket(newFd);

            newConn->localAddr = TOS_NODE_ID;
            newConn->localPort = destPort;
            newConn->remoteAddr = package->src;
            newConn->remotePort = srcPort;

            newConn->initialReceiveSequence = seq;

            initialSeq = (uint16_t)(
                TOS_NODE_ID * 100 + newFd * 10
            );

            newConn->initialSendSequence = initialSeq;
            newConn->controlRetries = 0;
            newConn->controlDeadline = 0;

            newConn->state = SYN_RCVD;

            if (sendControlPacket(
                    newConn,
                    TCP_FLAG_SYN | TCP_FLAG_ACK,
                    initialSeq,
                    (uint16_t)(seq + 1)
                ) != SUCCESS) {

                memset(newConn, 0, sizeof(socket_store_t));
                return FAIL;
            }

            dbg(TRANSPORT_CHANNEL,
                "Node %d received SYN from %d:%d, sent SYN-ACK\n",
                TOS_NODE_ID,
                package->src,
                srcPort);

            newConn->controlDeadline = call ControlTimer.getNow() + TRANSPORT_RTO_MS;

            if (newConn->controlDeadline == 0) 
            {
                newConn->controlDeadline = 1;
            }

            if (!call ControlTimer.isRunning()) 
            {
                call ControlTimer.startPeriodic(250);
            }

            return SUCCESS;
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

        if (conn->state == SYN_SENT &&
            flags == (TCP_FLAG_SYN | TCP_FLAG_ACK)) 
            {
                if (ack != (uint16_t)(
                        conn->initialSendSequence + 1)) {
                    return FAIL;
                }

            conn->initialReceiveSequence = seq;

            if (sendControlPacket(
                    conn,
                    TCP_FLAG_ACK,
                    (uint16_t)(conn->initialSendSequence + 1),
                    (uint16_t)(seq + 1)
                ) != SUCCESS) {
                return FAIL;
            }

            call TransportStream.initialize(
                conn,
                (uint16_t)(conn->initialSendSequence + 1),
                (uint16_t)(seq + 1),
                window
            );

            conn->controlRetries = 0;
            conn->controlDeadline = 0;
            conn->state = ESTABLISHED;

            dbg(TRANSPORT_CHANNEL,
                "Node %d: Client TCP ESTABLISHED fd=%d\n",
                TOS_NODE_ID, fd);

            signal Transport.connectDone(fd, SUCCESS);
            return SUCCESS;
        }

        if (conn->state == SYN_RCVD &&
            flags == TCP_FLAG_ACK) {

            if (ack != (uint16_t)(
                    conn->initialSendSequence + 1) ||
                seq != (uint16_t)(
                    conn->initialReceiveSequence + 1)) {
                return FAIL;
            }

            call TransportStream.initialize(
                conn,
                (uint16_t)(conn->initialSendSequence + 1),
                (uint16_t)(conn->initialReceiveSequence + 1),
                window
            );

            conn->controlRetries = 0;
            conn->controlDeadline = 0;
            conn->state = ESTABLISHED;

            dbg(TRANSPORT_CHANNEL,
                "Node %d: Server TCP ESTABLISHED fd=%d\n",
                TOS_NODE_ID, fd);

            {
                socket_t listenFd = findListener(conn->localPort);

                if (listenFd != 0) {
                    signal Transport.acceptDone(listenFd, fd);
                }
            }

            return SUCCESS;
        }

        if (conn->state == ESTABLISHED &&
            flags == (TCP_FLAG_SYN | TCP_FLAG_ACK) &&
            seq == conn->initialReceiveSequence &&
            ack == (uint16_t)(
                conn->initialSendSequence + 1)) {

            return sendControlPacket(
                conn,
                TCP_FLAG_ACK,
                conn->sendNext,
                conn->receiveNext
            );
        }

        if (flags & (TCP_FLAG_SYN | TCP_FLAG_FIN)) 
        {
            return FAIL;
        }

        if (conn->state != ESTABLISHED &&
            conn->state != CLOSE_WAIT &&
            conn->state != FIN_WAIT_1 &&
            conn->state != FIN_WAIT_2) {
            return FAIL;
        }


        if (flags & TCP_FLAG_ACK) 
        {
            result = call TransportStream.onAck(
                conn, ack, window
            );
        }

        if (flags & TCP_FLAG_DATA) 
        {
            result = call TransportStream.onData(
                conn,
                seq,
                (uint8_t*)&package->payload[TRANSPORT_HEADER_SIZE],
                length
            );
        }

        if (!(flags & (TCP_FLAG_ACK | TCP_FLAG_DATA))) 
        {
            return FAIL;
        }

        return result;
    }

    command error_t Transport.close(socket_t fd) 
    {
        return FAIL;
    }

    command error_t Transport.release(socket_t fd) 
    {
        socket_store_t* conn = getSocket(fd);

        if (conn == NULL || conn->state != CLOSED) 
        {
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

    event void ControlTimer.fired() {
        uint8_t i;
        uint32_t now = call ControlTimer.getNow();
        bool pending = FALSE;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) 
        {
            socket_store_t* conn = &sockets[i];
            uint8_t flags;
            uint16_t ack;

            if (!conn->inUse) 
            {
                continue;
            }

            if (conn->state != SYN_SENT &&
                conn->state != SYN_RCVD) {
                continue;
            }

            if (conn->controlDeadline == 0) 
            {
                continue;
            }

            if ((int32_t)(now - conn->controlDeadline) < 0) 
            {
                pending = TRUE;
                continue;
            }

            if (conn->controlRetries >= TRANSPORT_MAX_RETRIES) 
            {
                socket_t fd = i + 1;

                dbg(TRANSPORT_CHANNEL,
                    "Node %d: TCP handshake timeout fd=%d\n",
                    TOS_NODE_ID, fd);

                if (conn->state == SYN_SENT) 
                {
                    conn->state = CLOSED;
                    conn->remoteAddr = 0;
                    conn->remotePort = 0;
                    conn->controlRetries = 0;
                    conn->controlDeadline = 0;

                    signal Transport.connectDone(fd, FAIL);
                } else 
                {
                    memset(conn, 0, sizeof(socket_store_t));
                }

                continue;
            }

            if (conn->state == SYN_SENT) 
            {
                flags = TCP_FLAG_SYN;
                ack = 0;
            } 
            else 
            {
                flags = TCP_FLAG_SYN | TCP_FLAG_ACK;
                ack = (uint16_t)(
                    conn->initialReceiveSequence + 1
                );
            }

            if (sendControlPacket(
                    conn,
                    flags,
                    conn->initialSendSequence,
                    ack
                ) == SUCCESS) {

                dbg(TRANSPORT_CHANNEL,
                    "Node %d retransmitted TCP control flags=%d fd=%d\n",
                    TOS_NODE_ID, flags, i + 1);
            }

            conn->controlRetries++;

            conn->controlDeadline =
                now + TRANSPORT_RTO_MS;

            if (conn->controlDeadline == 0) 
            {
                conn->controlDeadline = 1;
            }

            pending = TRUE;
        }

        if (!pending) 
        {
            call ControlTimer.stop();
        }
    }

}