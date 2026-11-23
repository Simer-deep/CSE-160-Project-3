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
}
implementation 
{
   socket_t serverSocket = 0;
   socket_t clientSocket = 0;

   event void Boot.booted() {
      call AMControl.start();
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err) {
      if (err == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.start();
         call DV.start();
         call DVExchange.start();
      } else {
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err) {}

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
      call IPRouting.ping(destination, payload);
   }

   event void CommandHandler.printNeighbors() {
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
      call DV.printTable();
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer() 
   {
      socket_addr_t address;

      if (serverSocket != 0) 
      {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Server already started\n",
             TOS_NODE_ID);
         return;
      }

      serverSocket = call Transport.socket();

      if (serverSocket == 0) 
      {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Server socket allocation failed\n",
             TOS_NODE_ID);
         return;
      }

      address.addr = TOS_NODE_ID;
      address.port = 20;

      if (call Transport.bind(serverSocket, &address)
          != SUCCESS) {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Server bind failed\n",
             TOS_NODE_ID);
         call Transport.release(serverSocket);
         serverSocket = 0;
         return;
      }

      if (call Transport.listen(serverSocket) != SUCCESS) 
      {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Server listen failed\n",
             TOS_NODE_ID);
         call Transport.release(serverSocket);
         serverSocket = 0;
         return;
      }

      dbg(TRANSPORT_CHANNEL,
          "Node %d: TCP server LISTENING on port 20\n",
          TOS_NODE_ID);
   }

   event void CommandHandler.setTestClient() 
   {
      socket_addr_t localAddress;
      socket_addr_t serverAddress;

      if (clientSocket != 0) 
      {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Client already started\n",
             TOS_NODE_ID);
         return;
      }

      clientSocket = call Transport.socket();

      if (clientSocket == 0) 
      {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Client socket allocation failed\n",
             TOS_NODE_ID);
         return;
      }

      localAddress.addr = TOS_NODE_ID;
      localAddress.port = 10;

      if (call Transport.bind(clientSocket, &localAddress)
          != SUCCESS) {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Client bind failed\n",
             TOS_NODE_ID);
         call Transport.release(clientSocket);
         clientSocket = 0;
         return;
      }

      serverAddress.addr = 1;
      serverAddress.port = 20;

      if (call Transport.connect(clientSocket, &serverAddress)
          != SUCCESS) {
         dbg(TRANSPORT_CHANNEL,
             "Node %d: Client connect request failed\n",
             TOS_NODE_ID);
         call Transport.release(clientSocket);
         clientSocket = 0;
         return;
      }

      dbg(TRANSPORT_CHANNEL,
          "Node %d: TCP client connecting to Node 1 port 20\n",
          TOS_NODE_ID);
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   event void IPRouting.transportReceived(pack* packet) 
   {
      if (packet == NULL) 
      {
         return;
      }

      dbg(TRANSPORT_CHANNEL,
         "Node %d received TCP packet from %d\n",
         TOS_NODE_ID, packet->src);

      call Transport.receive(packet);
   }

   event void Transport.connectDone(
      socket_t fd,
      error_t result
   ) {
      dbg(TRANSPORT_CHANNEL,
         "Node %d: TCP client connected fd=%d result=%d\n",
         TOS_NODE_ID, fd, result);
   }

   event void Transport.acceptDone(
      socket_t listenFd,
      socket_t connectedFd
   ) {
      dbg(TRANSPORT_CHANNEL,
         "Node %d: TCP server accepted connection fd=%d listener=%d\n",
         TOS_NODE_ID, connectedFd, listenFd);
   }

   event void Transport.closeDone(
      socket_t fd,
      error_t result
   ) {
      dbg(TRANSPORT_CHANNEL,
         "Node %d: TCP connection closed fd=%d result=%d\n",
         TOS_NODE_ID, fd, result);
   }
}
