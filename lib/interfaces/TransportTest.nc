#include "../../includes/transport_test.h"

interface TransportTest {
    command error_t startProducer(socket_t socketId, socket_store_t* socket,
        uint32_t totalBytes);
    command error_t startConsumer(socket_t socketId, socket_store_t* socket,
        uint32_t expectedBytes);
    command error_t pause(socket_store_t* socket);
    command error_t resume(socket_store_t* socket);
    command error_t getStats(socket_store_t* socket,
        transport_test_stats_t* stats);
    command error_t stop(socket_store_t* socket);

    event void bytesQueued(socket_store_t* socket);
    event void finished(socket_store_t* socket, error_t result);
}
