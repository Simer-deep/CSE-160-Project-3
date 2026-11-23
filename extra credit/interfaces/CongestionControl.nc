#include "../../includes/socket.h"

interface CongestionControl {
    command void start(socket_store_t* socket);
    command void acknowledged(socket_store_t* socket, uint16_t bytes);
    command void timedOut(socket_store_t* socket);
    command uint16_t window(socket_store_t* socket);
}
