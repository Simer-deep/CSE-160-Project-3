#include "../../includes/transport_test.h"
#include <Timer.h>
#include <string.h>

module TransportTestP {
    provides interface TransportTest;
    uses interface Transport;
    uses interface Timer<TMilli> as TestTimer;
}

implementation {
    typedef struct test_connection_t {
        socket_store_t* socket;
        socket_t socketId;
        bool producing;
        bool consuming;
        bool allBytesQueued;
        bool resultSent;
        uint32_t totalBytes;
        uint32_t expectedBytes;
        transport_test_stats_t stats;
    } test_connection_t;

    test_connection_t connections[MAX_NUM_OF_SOCKETS];

    test_connection_t* findConnection(socket_store_t* socket) {
        uint8_t i;

        if(socket == NULL) {
            return NULL;
        }

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(connections[i].socket == socket) {
                return &connections[i];
            }
        }

        return NULL;
    }

    test_connection_t* addConnection(socket_t socketId, socket_store_t* socket) {
        test_connection_t* connection;
        uint8_t i;

        if(socket == NULL || !socket->inUse || socket->state != ESTABLISHED) {
            return NULL;
        }

        connection = findConnection(socket);
        if(connection != NULL) {
            if(connection->socketId != socketId || connection->resultSent) {
                return NULL;
            }
            return connection;
        }

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(connections[i].socket != NULL && connections[i].socketId == socketId) {
                return NULL;
            }
        }

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(connections[i].socket == NULL) {
                connection = &connections[i];
                memset(connection, 0, sizeof(test_connection_t));
                connection->socket = socket;
                connection->socketId = socketId;
                return connection;
            }
        }

        return NULL;
    }

    void startTimer() {
        if(!call TestTimer.isRunning()) {
            call TestTimer.startPeriodic(TRANSPORT_TEST_INTERVAL_MS);
        }
    }

    command error_t TransportTest.startProducer(socket_t socketId,
        socket_store_t* socket, uint32_t totalBytes) {
        test_connection_t* connection;

        if(socket == NULL || socket->sendUsed != 0 || socket->closeRequested ||
            socket->finSent) {
            return FAIL;
        }

        connection = addConnection(socketId, socket);
        if(connection == NULL || connection->producing) {
            return FAIL;
        }

        connection->producing = TRUE;
        connection->totalBytes = totalBytes;
        startTimer();
        return SUCCESS;
    }

    command error_t TransportTest.startConsumer(socket_t socketId,
        socket_store_t* socket, uint32_t expectedBytes) {
        test_connection_t* connection;

        connection = addConnection(socketId, socket);
        if(connection == NULL || connection->consuming) {
            return FAIL;
        }

        connection->consuming = TRUE;
        connection->expectedBytes = expectedBytes;
        startTimer();
        return SUCCESS;
    }

    command error_t TransportTest.pause(socket_store_t* socket) {
        test_connection_t* connection;

        connection = findConnection(socket);
        if(connection == NULL || !connection->consuming ||
            connection->resultSent) {
            return FAIL;
        }

        connection->stats.paused = TRUE;
        return SUCCESS;
    }

    command error_t TransportTest.resume(socket_store_t* socket) {
        test_connection_t* connection;

        connection = findConnection(socket);
        if(connection == NULL || !connection->consuming ||
            connection->resultSent) {
            return FAIL;
        }

        connection->stats.paused = FALSE;
        return SUCCESS;
    }

    command error_t TransportTest.getStats(socket_store_t* socket,
        transport_test_stats_t* stats) {
        test_connection_t* connection;

        connection = findConnection(socket);
        if(connection == NULL || stats == NULL) {
            return FAIL;
        }

        *stats = connection->stats;
        return SUCCESS;
    }

    command error_t TransportTest.stop(socket_store_t* socket) {
        test_connection_t* connection;

        connection = findConnection(socket);
        if(connection == NULL) {
            return FAIL;
        }

        memset(connection, 0, sizeof(test_connection_t));
        return SUCCESS;
    }

    error_t produceBytes(test_connection_t* connection) {
        socket_store_t* socket;
        uint8_t buffer[TRANSPORT_TEST_CHUNK_SIZE];
        uint16_t count;
        uint16_t written;
        uint8_t i;
        uint32_t remaining;

        if(connection->allBytesQueued) {
            return SUCCESS;
        }

        socket = connection->socket;
        remaining = connection->totalBytes - connection->stats.accepted;
        count = sizeof(buffer);
        if(remaining < count) {
            count = remaining;
        }

        if(count > 0) {
            if(socket->state != ESTABLISHED || socket->closeRequested ||
                socket->finSent) {
                return FAIL;
            }

            for(i = 0; i < count; i++) {
                buffer[i] = (connection->stats.accepted + i) % 256;
            }

            written = call Transport.write(connection->socketId, buffer, count);
            if(written > count) {
                return FAIL;
            }
            connection->stats.accepted += written;
        }

        if(connection->stats.accepted == connection->totalBytes) {
            connection->allBytesQueued = TRUE;
        }

        return SUCCESS;
    }

    error_t consumeBytes(test_connection_t* connection) {
        uint8_t buffer[TRANSPORT_TEST_CHUNK_SIZE];
        uint16_t count;
        uint8_t i;

        count = call Transport.read(connection->socketId, buffer, sizeof(buffer));
        if(count > sizeof(buffer)) {
            return FAIL;
        }

        for(i = 0; i < count; i++) {
            if(buffer[i] != (connection->stats.consumed + i) % 256) {
                connection->stats.mismatches++;
            }
        }

        connection->stats.consumed += count;
        return SUCCESS;
    }

    void runTest(test_connection_t* connection) {
        socket_store_t* socket;
        bool wasQueued;
        bool complete;

        socket = connection->socket;
        wasQueued = connection->allBytesQueued;

        if(!socket->inUse || socket->state == CLOSED) {
            connection->stats.failed = TRUE;
        }

        if(!connection->stats.failed && connection->producing) {
            if(produceBytes(connection) != SUCCESS ||
                socket->sendUsed > connection->stats.accepted) {
                connection->stats.failed = TRUE;
            } else {
                connection->stats.acknowledged =
                    connection->stats.accepted - socket->sendUsed;
                connection->stats.producerDone = connection->allBytesQueued &&
                    connection->stats.acknowledged == connection->totalBytes;
            }
        }

        if(!connection->stats.failed && connection->consuming &&
            !connection->stats.paused && !connection->stats.consumerDone) {
            if(consumeBytes(connection) != SUCCESS) {
                connection->stats.failed = TRUE;
            }
        }

        if(connection->consuming && socket->finReceived &&
            socket->receiveUsed == 0) {
            connection->stats.consumerDone = TRUE;
            if(connection->stats.consumed != connection->expectedBytes ||
                connection->stats.mismatches != 0) {
                connection->stats.failed = TRUE;
            }
        }

        complete = (!connection->producing || connection->stats.producerDone) &&
            (!connection->consuming || connection->stats.consumerDone);

        if(!wasQueued && connection->allBytesQueued) {
            signal TransportTest.bytesQueued(socket);
            if(connection->socket != socket) {
                return;
            }
        }

        if(complete || connection->stats.failed) {
            connection->resultSent = TRUE;
            signal TransportTest.finished(socket,
                connection->stats.failed ? FAIL : SUCCESS);
        }
    }

    event void TestTimer.fired() {
        uint8_t i;
        bool active = FALSE;

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(connections[i].socket != NULL && !connections[i].resultSent) {
                runTest(&connections[i]);
            }
        }

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(connections[i].socket != NULL && !connections[i].resultSent) {
                active = TRUE;
            }
        }

        if(!active) {
            call TestTimer.stop();
        }
    }
}
