#include "../../includes/transport.h"

module TransportStreamP {
    provides interface TransportStream;
}

implementation {
    bool isConnected(socket_store_t* socket) {
        return socket != NULL && socket->inUse &&
            (socket->state == ESTABLISHED || socket->state == CLOSE_WAIT ||
             socket->state == FIN_WAIT_1 || socket->state == FIN_WAIT_2);
    }

    command void TransportStream.initialize(socket_store_t* socket,
        uint16_t sendSeq, uint16_t receiveSeq, uint8_t peerWindow) {
        if (socket == NULL) {
            return;
        }

        socket->sndUna = sendSeq;
        socket->sndNxt = sendSeq;
        socket->sndEnd = sendSeq;
        socket->sendHead = 0;
        socket->sendUsed = 0;
        socket->sendWindow = TRANSPORT_SEND_WINDOW;
        socket->peerWnd = peerWindow;

        if (socket->peerWnd > SOCKET_BUFFER_SIZE) {
            socket->peerWnd = SOCKET_BUFFER_SIZE;
        }

        socket->rcvNxt = receiveSeq;
        socket->recvHead = 0;
        socket->recvUsed = 0;
        socket->dataDeadline = 0;
        socket->dataRetries = 0;
    }

    command uint16_t TransportStream.write(socket_store_t* socket,
        uint8_t* buffer, uint16_t length) {
        uint16_t count;
        uint16_t i;

        if (!isConnected(socket) || buffer == NULL ||
            socket->state != ESTABLISHED || socket->closeRequested ||
            socket->finSent) {
            return 0;
        }

        count = SOCKET_BUFFER_SIZE - socket->sendUsed;
        if (count > length) {
            count = length;
        }

        for (i = 0; i < count; i++) {
            socket->sendBuff[(socket->sendHead + socket->sendUsed + i) %
                SOCKET_BUFFER_SIZE] = buffer[i];
        }

        socket->sendUsed += count;
        socket->sndEnd += count;
        return count;
    }

    command uint16_t TransportStream.read(socket_store_t* socket,
        uint8_t* buffer, uint16_t length) {
        uint16_t count;
        uint16_t i;

        if (socket == NULL || !socket->inUse || buffer == NULL) {
            return 0;
        }

        count = socket->recvUsed;
        if (count > length) {
            count = length;
        }

        for (i = 0; i < count; i++) {
            buffer[i] = socket->rcvdBuff[(socket->recvHead + i) %
                SOCKET_BUFFER_SIZE];
        }

        socket->recvHead = (socket->recvHead + count) % SOCKET_BUFFER_SIZE;
        socket->recvUsed -= count;

        if (count > 0 && isConnected(socket)) {
            signal TransportStream.ackNeeded(socket, socket->rcvNxt,
                SOCKET_BUFFER_SIZE - socket->recvUsed);
        }

        return count;
    }

    command error_t TransportStream.onData(socket_store_t* socket,
        uint16_t sequence, uint8_t* data, uint8_t length) {
        uint8_t i;
        error_t result = FAIL;

        if (!isConnected(socket) || socket->state == CLOSE_WAIT ||
            socket->finReceived || data == NULL || length == 0 ||
            length > TRANSPORT_MAX_DATA_SIZE) {
            return FAIL;
        }

        if (sequence == socket->rcvNxt &&
            length <= SOCKET_BUFFER_SIZE - socket->recvUsed) {
            for (i = 0; i < length; i++) {
                socket->rcvdBuff[(socket->recvHead + socket->recvUsed + i) %
                    SOCKET_BUFFER_SIZE] = data[i];
            }

            socket->recvUsed += length;
            socket->rcvNxt += length;
            result = SUCCESS;
        }

        signal TransportStream.ackNeeded(socket, socket->rcvNxt,
            SOCKET_BUFFER_SIZE - socket->recvUsed);
        return result;
    }

    command error_t TransportStream.onAck(socket_store_t* socket,
        uint16_t acknowledgement, uint8_t window) {
        uint16_t acknowledged;
        uint16_t outstanding;

        if (!isConnected(socket) || window > SOCKET_BUFFER_SIZE) {
            return FAIL;
        }

        acknowledged = (uint16_t)(acknowledgement - socket->sndUna);
        outstanding = (uint16_t)(socket->sndNxt - socket->sndUna);

        if (acknowledged > outstanding || acknowledged > socket->sendUsed) {
            return FAIL;
        }

        socket->sendHead = (socket->sendHead + acknowledged) %
            SOCKET_BUFFER_SIZE;
        socket->sendUsed -= acknowledged;
        socket->sndUna = acknowledgement;
        socket->peerWnd = window;

        if (acknowledged > 0) {
            socket->dataRetries = 0;
        }

        if (socket->sndUna == socket->sndNxt) {
            socket->dataDeadline = 0;
        }

        return SUCCESS;
    }
}
