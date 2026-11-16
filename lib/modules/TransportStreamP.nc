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

    uint8_t receiveWindow(socket_store_t* socket) {
        if (socket == NULL || !socket->inUse ||
            socket->receiveUsed > SOCKET_BUFFER_SIZE) {
            return 0;
        }

        return SOCKET_BUFFER_SIZE - socket->receiveUsed;
    }

    error_t sendAck(socket_store_t* socket) {
        error_t result;

        result = signal TransportStream.sendSegment(socket, TCP_FLAG_ACK,
            socket->sendNext, socket->receiveNext, receiveWindow(socket),
            NULL, 0);

        if (result != SUCCESS) {
            socket->windowDeadline = 0;
        }

        return result;
    }

    error_t sendData(socket_store_t* socket, uint16_t offset, uint8_t length) {
        uint8_t data[TRANSPORT_MAX_DATA_SIZE];
        uint8_t i;

        for (i = 0; i < length; i++) {
            data[i] = socket->sendBuffer[(socket->sendHead + offset + i) %
                SOCKET_BUFFER_SIZE];
        }

        return signal TransportStream.sendSegment(socket, TCP_FLAG_DATA,
            (uint16_t)(socket->sendUnacked + offset), socket->receiveNext,
            receiveWindow(socket), data, length);
    }

    command void TransportStream.initialize(socket_store_t* socket,
        uint16_t sendSequence, uint16_t receiveSequence, uint8_t peerWindow) {
        if (socket == NULL) {
            return;
        }

        socket->sendUnacked = sendSequence;
        socket->sendNext = sendSequence;
        socket->sendEnd = sendSequence;
        socket->sendHead = 0;
        socket->sendUsed = 0;
        socket->sendWindow = TRANSPORT_SEND_WINDOW;
        socket->peerWindow = peerWindow;

        if (socket->peerWindow > SOCKET_BUFFER_SIZE) {
            socket->peerWindow = SOCKET_BUFFER_SIZE;
        }

        socket->receiveNext = receiveSequence;
        socket->receiveHead = 0;
        socket->receiveUsed = 0;
        socket->dataDeadline = 0;
        socket->dataRetries = 0;
        socket->windowDeadline = 0;
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
            socket->sendBuffer[(socket->sendHead + socket->sendUsed + i) %
                SOCKET_BUFFER_SIZE] = buffer[i];
        }

        socket->sendUsed += count;
        socket->sendEnd += count;
        return count;
    }

    command uint16_t TransportStream.read(socket_store_t* socket,
        uint8_t* buffer, uint16_t length) {
        uint16_t count;
        uint16_t i;

        if (socket == NULL || !socket->inUse || buffer == NULL) {
            return 0;
        }

        count = socket->receiveUsed;
        if (count > length) {
            count = length;
        }

        for (i = 0; i < count; i++) {
            buffer[i] = socket->receiveBuffer[(socket->receiveHead + i) %
                SOCKET_BUFFER_SIZE];
        }

        socket->receiveHead = (socket->receiveHead + count) % SOCKET_BUFFER_SIZE;
        socket->receiveUsed -= count;

        if (count > 0 && isConnected(socket)) {
            sendAck(socket);
        }

        return count;
    }

    command error_t TransportStream.onData(socket_store_t* socket,
        uint16_t sequence, uint8_t* data, uint8_t length) {
        uint8_t i;
        error_t result = FAIL;

        if (socket == NULL || !socket->inUse || data == NULL || length == 0 ||
            length > TRANSPORT_MAX_DATA_SIZE) {
            return FAIL;
        }

        if (!isConnected(socket) && socket->state != LAST_ACK &&
            socket->state != CLOSING && socket->state != TIME_WAIT) {
            return FAIL;
        }

        if (!socket->finReceived &&
            (socket->state == ESTABLISHED || socket->state == FIN_WAIT_1 ||
             socket->state == FIN_WAIT_2) &&
            sequence == socket->receiveNext &&
            length <= SOCKET_BUFFER_SIZE - socket->receiveUsed) {
            for (i = 0; i < length; i++) {
                socket->receiveBuffer[(socket->receiveHead + socket->receiveUsed + i) %
                    SOCKET_BUFFER_SIZE] = data[i];
            }

            socket->receiveUsed += length;
            socket->receiveNext += length;
            result = SUCCESS;
        }

        sendAck(socket);
        return result;
    }

    command error_t TransportStream.onAck(socket_store_t* socket,
        uint16_t acknowledgement, uint8_t window) {
        uint16_t acknowledged;
        uint16_t outstanding;

        if (!isConnected(socket) || window > SOCKET_BUFFER_SIZE) {
            return FAIL;
        }

        acknowledged = (uint16_t)(acknowledgement - socket->sendUnacked);
        outstanding = (uint16_t)(socket->sendNext - socket->sendUnacked);

        if (acknowledged > outstanding || acknowledged > socket->sendUsed) {
            return FAIL;
        }

        socket->sendHead = (socket->sendHead + acknowledged) %
            SOCKET_BUFFER_SIZE;
        socket->sendUsed -= acknowledged;
        socket->sendUnacked = acknowledgement;
        socket->peerWindow = window;

        if (acknowledged > 0) {
            socket->dataRetries = 0;
            socket->dataDeadline = 0;
        }

        if (socket->sendUnacked == socket->sendNext) {
            socket->dataDeadline = 0;
        }

        return SUCCESS;
    }

    command bool TransportStream.isDrained(socket_store_t* socket) {
        return isConnected(socket) && socket->sendUsed == 0 &&
            socket->sendUnacked == socket->sendNext &&
            socket->sendNext == socket->sendEnd;
    }

    command uint8_t TransportStream.getReceiveWindow(socket_store_t* socket) {
        return receiveWindow(socket);
    }

    command error_t TransportStream.onTick(socket_store_t* socket,
        uint32_t now) {
        uint16_t outstanding;
        uint16_t limit;
        uint16_t offset;
        uint16_t length;
        uint8_t sent;

        if (socket == NULL || !socket->inUse) {
            return FAIL;
        }

        if (!isConnected(socket) && socket->state != LAST_ACK &&
            socket->state != CLOSING && socket->state != TIME_WAIT) {
            return FAIL;
        }

        if (socket->windowDeadline == 0 ||
            (int32_t)(now - socket->windowDeadline) >= 0) {
            if (sendAck(socket) == SUCCESS) {
                socket->windowDeadline = now + TRANSPORT_RTO_MS;
                if (socket->windowDeadline == 0) {
                    socket->windowDeadline = 1;
                }
            }
        }

        if (socket->sendUsed == 0) {
            socket->dataDeadline = 0;
            socket->dataRetries = 0;
            return SUCCESS;
        }

        if (socket->finSent || (socket->state != ESTABLISHED &&
            socket->state != CLOSE_WAIT)) {
            return FAIL;
        }

        outstanding = (uint16_t)(socket->sendNext - socket->sendUnacked);
        if (outstanding > socket->sendUsed ||
            socket->sendUsed > SOCKET_BUFFER_SIZE) {
            return FAIL;
        }

        if (socket->peerWindow == 0) {
            socket->dataDeadline = 0;
            socket->dataRetries = 0;
            return SUCCESS;
        }

        limit = socket->sendWindow;
        if (limit > SOCKET_BUFFER_SIZE) {
            limit = SOCKET_BUFFER_SIZE;
        }
        if (limit > socket->peerWindow) {
            limit = socket->peerWindow;
        }

        if (socket->dataDeadline == 0) {
            socket->dataDeadline = now + TRANSPORT_RTO_MS;
            if (socket->dataDeadline == 0) {
                socket->dataDeadline = 1;
            }
        } else if ((int32_t)(now - socket->dataDeadline) >= 0) {
            if (socket->dataRetries >= TRANSPORT_MAX_RETRIES) {
                return FAIL;
            }

            socket->dataRetries++;
            socket->dataDeadline = now + TRANSPORT_RTO_MS;
            if (socket->dataDeadline == 0) {
                socket->dataDeadline = 1;
            }

            for (offset = 0; offset < outstanding && offset < limit;
                offset += length) {
                length = outstanding - offset;
                if (length > limit - offset) {
                    length = limit - offset;
                }
                if (length > TRANSPORT_MAX_DATA_SIZE) {
                    length = TRANSPORT_MAX_DATA_SIZE;
                }
                if (sendData(socket, offset, length) != SUCCESS) {
                    return SUCCESS;
                }
            }

            if (outstanding > 0) {
                return SUCCESS;
            }
        }

        for (sent = 0; sent < 2 && outstanding < limit &&
            outstanding < socket->sendUsed; sent++) {
            length = socket->sendUsed - outstanding;
            if (length > limit - outstanding) {
                length = limit - outstanding;
            }
            if (length > TRANSPORT_MAX_DATA_SIZE) {
                length = TRANSPORT_MAX_DATA_SIZE;
            }
            if (sendData(socket, outstanding, length) != SUCCESS) {
                return SUCCESS;
            }

            socket->sendNext += length;
            outstanding += length;
        }

        return SUCCESS;
    }
}
