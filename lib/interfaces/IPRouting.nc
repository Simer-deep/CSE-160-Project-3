#include "../../includes/packet.h"

interface IPRouting {

    command void ping(uint16_t destination, uint8_t* payload);

    command error_t sendTransport(
        uint16_t destination,
        uint8_t* payload,
        uint8_t length
    );

    command void setTestDrop(uint16_t source, uint16_t destination,
        uint8_t srcPort, uint8_t destPort, uint8_t flags,
        uint16_t sequence, uint16_t acknowledgement,
        uint8_t windowMode, uint8_t count);

    event void transportReceived(
        pack* packet
    );

}
