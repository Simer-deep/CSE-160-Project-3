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
    command error_t onTick(socket_store_t* socket, uint32_t now);
    command bool isDrained(socket_store_t* socket);
    command uint8_t getReceiveWindow(socket_store_t* socket);

    event error_t sendSegment(socket_store_t* socket, uint8_t flags,
        uint16_t sequence, uint16_t acknowledgement, uint8_t window,
        uint8_t* data, uint8_t length);
}
