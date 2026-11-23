#include "includes/channels.h"
#include "includes/transport.h"

module Node {
    uses interface Boot;
    uses interface SplitControl as AMControl;
    uses interface CommandHandler;
    uses interface NeighborDiscovery;
    uses interface Flooding;
    uses interface DVExchange;
    uses interface IPRouting;
    uses interface DistanceVector as DV;
    uses interface Transport;
    uses interface TransportTest;
}

implementation {

   socket_t serverSocket = 0;
   socket_t clientSocket = 0;
   socket_t acceptedSocket = 0;

    typedef struct test_request_t {
        bool inUse;
        bool paused;
        uint16_t remoteAddr;
        uint8_t srcPort;
        uint8_t destPort;
        uint32_t bytes;
        socket_t socketId;
    } test_request_t;

    test_request_t requests[MAX_NUM_OF_SOCKETS];
    uint32_t clientBytes[MAX_NUM_OF_SOCKETS + 1];

    socket_t findSocket(uint16_t remote, uint8_t srcPort, uint8_t destPort) {
        socket_t fd;
        socket_store_t* socket;

        for(fd = 1; fd <= MAX_NUM_OF_SOCKETS; fd++) {
            socket = call Transport.getSocketState(fd);
            if(socket != NULL && socket->localPort == srcPort &&
                socket->remoteAddr == remote &&
                socket->remotePort == destPort) {
                return fd;
            }
        }

        return 0;
    }

    test_request_t* findRequest(uint16_t remote, uint8_t srcPort,
        uint8_t destPort) {
        uint8_t i;

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(requests[i].inUse && requests[i].remoteAddr == remote &&
                requests[i].srcPort == srcPort &&
                requests[i].destPort == destPort) {
                return &requests[i];
            }
        }

        return NULL;
    }

    event void Boot.booted() {
        call AMControl.start();
        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    event void AMControl.startDone(error_t err) {
        if(err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
            call NeighborDiscovery.start();
            call DV.start();
            call DVExchange.start();
        } else {
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err) {}

    event void CommandHandler.ping(uint16_t destination, uint8_t* payload) {
        call IPRouting.ping(destination, payload);
    }

    event void CommandHandler.printNeighbors() {
        call NeighborDiscovery.printNeighbors();
    }

    event void CommandHandler.printRouteTable() {
        call DV.printTable();
    }

    event void CommandHandler.printLinkState() {}
    event void CommandHandler.printDistanceVector() {}

    event void CommandHandler.setTestServer(uint8_t port) {
        socket_t fd;
        socket_store_t* socket;
        socket_addr_t address;

        if(port == 0) {
            return;
        }

        for(fd = 1; fd <= MAX_NUM_OF_SOCKETS; fd++) {
            socket = call Transport.getSocketState(fd);
            if(socket != NULL && socket->state == LISTEN &&
                socket->localPort == port) {
                return;
            }
        }

        fd = call Transport.socket();
        if(fd == 0) {
            dbg(TRANSPORT_CHANNEL, "Node %u could not open server port %u\n",
                TOS_NODE_ID, port);
            return;
        }

        address.addr = TOS_NODE_ID;
        address.port = port;

        if(call Transport.bind(fd, &address) != SUCCESS ||
            call Transport.listen(fd) != SUCCESS) {
            call Transport.release(fd);
            dbg(TRANSPORT_CHANNEL, "Node %u could not listen on port %u\n",
                TOS_NODE_ID, port);
            return;
        }

        dbg(TRANSPORT_CHANNEL, "Node %u listening on port %u\n",
            TOS_NODE_ID, port);
    }

    event void CommandHandler.setTestExpected(uint16_t remote, uint8_t srcPort,
        uint8_t destPort, uint32_t length) {
        uint8_t i;
        test_request_t* request;

        request = findRequest(remote, destPort, srcPort);
        if(request == NULL) {
            for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if(!requests[i].inUse) {
                    request = &requests[i];
                    break;
                }
            }
        }

        if(request == NULL) {
            dbg("transport_test", "Node %u has no free test records\n",
                TOS_NODE_ID);
            return;
        }

        request->inUse = TRUE;
        request->paused = FALSE;
        request->remoteAddr = remote;
        request->srcPort = destPort;
        request->destPort = srcPort;
        request->bytes = length;
        request->socketId = 0;
    }

    event void CommandHandler.setTestClient(uint16_t remote, uint8_t srcPort,
        uint8_t destPort, uint32_t length) {
        socket_addr_t local;
        socket_addr_t destination;
        socket_t fd;

        if(srcPort == 0 || destPort == 0 || remote == TOS_NODE_ID ||
            findSocket(remote, srcPort, destPort) != 0) {
            return;
        }

        fd = call Transport.socket();
        if(fd == 0) {
            dbg("transport_test", "Node %u could not allocate client socket\n",
                TOS_NODE_ID);
            return;
        }

        local.addr = TOS_NODE_ID;
        local.port = srcPort;
        destination.addr = remote;
        destination.port = destPort;

        if(call Transport.bind(fd, &local) != SUCCESS ||
            call Transport.connect(fd, &destination) != SUCCESS) {
            call Transport.release(fd);
            dbg("transport_test", "Node %u could not connect to %u:%u\n",
                TOS_NODE_ID, remote, destPort);
            return;
        }

        clientBytes[fd] = length;
        dbg("transport_test", "Node %u connecting to %u:%u for %lu bytes\n",
            TOS_NODE_ID, remote, destPort, (unsigned long)length);
    }

    event void CommandHandler.setTestClose(uint16_t remote,
        uint8_t srcPort, uint8_t destPort) {
        socket_t fd = findSocket(remote, srcPort, destPort);

        if(fd == 0 || call Transport.close(fd) != SUCCESS) {
            dbg("transport_test", "Node %u could not close connection\n",
                TOS_NODE_ID);
        }
    }

    event void CommandHandler.setTestPause(uint16_t remote,
        uint8_t srcPort, uint8_t destPort) {
        test_request_t* request = findRequest(remote, destPort, srcPort);
        socket_store_t* socket;

        if(request == NULL) {
            return;
        }

        request->paused = TRUE;
        socket = call Transport.getSocketState(request->socketId);

        if(socket != NULL) {
            call TransportTest.pause(socket);
        }

        dbg("transport_test", "Node %u paused the receiver\n", TOS_NODE_ID);
    }

    event void CommandHandler.setTestResume(uint16_t remote,
        uint8_t srcPort, uint8_t destPort) {
        test_request_t* request = findRequest(remote, destPort, srcPort);
        socket_store_t* socket;

        if(request == NULL) {
            return;
        }

        request->paused = FALSE;
        socket = call Transport.getSocketState(request->socketId);

        if(socket != NULL) {
            call TransportTest.resume(socket);
        }

        dbg("transport_test", "Node %u resumed the receiver\n", TOS_NODE_ID);
    }

    event void CommandHandler.setTestDrop(uint16_t source,
        uint16_t destination, uint8_t srcPort, uint8_t destPort,
        uint8_t flags, uint16_t sequence, uint16_t acknowledgement,
        uint8_t windowMode, uint8_t count) {
        call IPRouting.setTestDrop(source, destination, srcPort, destPort,
            flags, sequence, acknowledgement, windowMode, count);
    }

    event void CommandHandler.setAppServer() {}
    event void CommandHandler.setAppClient() {}

    event void IPRouting.transportReceived(pack* packet) {
        if(packet != NULL) {
            call Transport.receive(packet);
        }
    }

    event void Transport.connectDone(socket_t fd, error_t result) {
        socket_store_t* socket = call Transport.getSocketState(fd);

        if(result != SUCCESS || socket == NULL) {
            dbg("transport_test", "Node %u connection failed fd=%u\n",
                TOS_NODE_ID, fd);
            if(socket != NULL && socket->state == CLOSED) {
                if(call Transport.release(fd) == SUCCESS) {
                    dbg("transport_test",
                        "Node %u released failed socket fd=%u\n",
                        TOS_NODE_ID, fd);
                }
            }
            clientBytes[fd] = 0;
            return;
        }

        if(call TransportTest.startProducer(fd, socket,
            clientBytes[fd]) != SUCCESS) {
            dbg("transport_test", "Node %u could not start sender fd=%u\n",
                TOS_NODE_ID, fd);
        }
    }

    event void Transport.acceptDone(socket_t listenFd, socket_t connectedFd) 
    {
        socket_store_t* socket = call Transport.getSocketState(connectedFd);
        test_request_t* request;
        acceptedSocket = connectedFd;

        if(socket == NULL) 
        {
            return;
        }

        request = findRequest(socket->remoteAddr,
            socket->localPort, socket->remotePort);

        if(request == NULL) {
            dbg("transport_test", "Node %u missing expected size for %u:%u\n",
                TOS_NODE_ID, socket->remoteAddr, socket->remotePort);
            return;
        }

        request->socketId = connectedFd;

        if(call TransportTest.startConsumer(connectedFd, socket,
            request->bytes) != SUCCESS) {
            dbg("transport_test", "Node %u could not start receiver fd=%u\n",
                TOS_NODE_ID, connectedFd);
            return;
        }

        if(request->paused) {
            call TransportTest.pause(socket);
        }

        dbg("transport_test", "Node %u accepted %u:%u expecting %lu bytes\n",
            TOS_NODE_ID, socket->remoteAddr, socket->remotePort,
            (unsigned long)request->bytes);
    }

    event void Transport.closeDone(socket_t fd, error_t result) {
        socket_store_t* socket = call Transport.getSocketState(fd);
        uint8_t i;

        dbg("transport_test", "Node %u closed fd=%u result=%u\n",
            TOS_NODE_ID, fd, result);

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(requests[i].inUse && requests[i].socketId == fd) {
                requests[i].inUse = FALSE;
            }
        }

        if(socket != NULL && socket->state == CLOSED) {
            call Transport.release(fd);
        }
        if(fd <= MAX_NUM_OF_SOCKETS) {
            clientBytes[fd] = 0;
        }
    }

    event void TransportTest.bytesQueued(socket_store_t* socket) {
        socket_t fd;

        if(socket == NULL) {
            return;
        }

        fd = findSocket(socket->remoteAddr,
            socket->localPort, socket->remotePort);
        if(fd != 0) {
            dbg("transport_test", "Node %u queued all data on fd=%u\n",
                TOS_NODE_ID, fd);
            call Transport.close(fd);
        }
    }

   
    event void TransportTest.finished(
        socket_store_t* socket,
        error_t result
    ) {
        dbg("transport_test",
            "Node %u: Transport test finished result=%u\n",
            TOS_NODE_ID, result);

        if(socket != NULL) {
            call TransportTest.stop(socket);
        }
    }
}
