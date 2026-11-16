#include "../../includes/packet.h"

interface IPRouting {

    command void ping(uint16_t destination, uint8_t* payload);

    command error_t sendTransport(
        uint16_t destination,
        uint8_t* payload,
        uint8_t length
    );

    event void transportReceived(
        pack* packet
    );

}