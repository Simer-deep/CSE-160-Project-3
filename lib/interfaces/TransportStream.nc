#include "../../includes/socket.h"

interface TransportStream {
    command void initialize(socket_store_t* socket, uint16_t sendSequence,
        uint16_t receiveSequence, uint8_t peerWindow);
    command uint16_t write(socket_store_t* socket, uint8_t* buffer,
        uint16_t length);
    command uint16_t read(socket_store_t* socket, uint8_t* buffer,
        uint16_t length);
    command error_t onData(socket_store_t* socket, uint16_t sequence,
        uint8_t* data, uint8_t length);
    command error_t onAck(socket_store_t* socket, uint16_t acknowledgement,
        uint8_t window);

    event void ackNeeded(socket_store_t* socket, uint16_t acknowledgement,
        uint8_t window);
}
