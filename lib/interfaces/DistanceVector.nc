#include "../../includes/dv.h"

interface DistanceVector {

    command void start();

    command uint8_t count();

    command bool entryAt(
        uint8_t index,
        uint16_t* destination,
        uint8_t* cost,
        uint16_t* nextHop
    );

    command void acceptEntry(
        uint16_t from,
        uint16_t destination,
        uint8_t cost
    );

    command bool lookup(
        uint16_t destination,
        uint16_t* nextHop,
        uint8_t* cost
    );

    command void printTable();
}
