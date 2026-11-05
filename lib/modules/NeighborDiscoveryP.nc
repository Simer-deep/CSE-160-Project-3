#include <Timer.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module NeighborDiscoveryP {
   provides interface NeighborDiscovery;
   uses interface Timer<TMilli> as NeighborTimer;
   uses interface Random;
   uses interface Receive;
   uses interface SimpleSend as Sender;
}
implementation {
   pack sendPackage;
   uint16_t sequenceNum = 0;
   uint16_t neighbors[15];
   uint16_t neighborDeadAge[15];
   uint8_t neighborCount = 0;

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, const void* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   //simple function to check if a node is a neighbor
   command bool NeighborDiscovery.isNeighbor(uint16_t nodeId){
      uint8_t i;

      for(i = 0; i < neighborCount; i++){

         if(neighbors[i] == nodeId){
            return TRUE;
         }

      }

      return FALSE;
   }

   command uint8_t NeighborDiscovery.getNeighborCount(){
      return neighborCount;
   }

   command bool NeighborDiscovery.getNeighborAt(uint8_t index, uint16_t *nodeId){
      if(index >= neighborCount){
         return FALSE;
      }
      *nodeId = neighbors[index];
      return TRUE;
   }

   //kill off old neighbors
   void ageNeighbors(){

      uint16_t i;
      i = 0;
      
      while (i < neighborCount){

         neighborDeadAge[i]++;

         if(neighborDeadAge[i] >= 3){
            neighbors[i] = neighbors[neighborCount - 1];
            neighborDeadAge[i] = neighborDeadAge[neighborCount - 1];

            neighborCount--;
         }
         else{
            i++;
         }
      }
   }


   void addOrRefreshNeighbor(uint16_t nodeID)
   {
      uint8_t i;

      for(i = 0; i < neighborCount; i++)
      {
         if(neighbors[i] == nodeID)
         {
            neighborDeadAge[i] = 0;
            return;
         }
      }

      if(neighborCount < 15)
      {
         neighbors[neighborCount] = nodeID;
         neighborDeadAge[neighborCount] = 0;
         neighborCount++;
      }
   }


   command void NeighborDiscovery.start() {
      if (!call NeighborTimer.isRunning()) {
         call NeighborTimer.startOneShot(3000 + (call Random.rand16() % 1000));
      }
   }

   event void NeighborTimer.fired()
   {
      uint8_t discoveryMsg[PACKET_MAX_PAYLOAD_SIZE] = "DISCOVERY";
      uint16_t jitter;

      ageNeighbors();

      makePack(
         &sendPackage,
         TOS_NODE_ID,
         AM_BROADCAST_ADDR,
         1,
         PROTOCOL_PING,
         sequenceNum,
         discoveryMsg,
         PACKET_MAX_PAYLOAD_SIZE
      );


      sequenceNum++;

      call Sender.send(sendPackage, AM_BROADCAST_ADDR);

      jitter = call Random.rand16() % 1000;
      call NeighborTimer.startOneShot(5000 + jitter);
   }


   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      pack* incoming;
      if (len != sizeof(pack)) return msg;
      incoming = (pack*) payload;
      if (incoming->src == TOS_NODE_ID || incoming->TTL != 1) return msg;

      if (incoming->protocol == PROTOCOL_PING && incoming->dest == AM_BROADCAST_ADDR) {
         makePack(&sendPackage, TOS_NODE_ID, incoming->src, 1,
            PROTOCOL_PINGREPLY, sequenceNum++, incoming->payload,
            PACKET_MAX_PAYLOAD_SIZE);
         call Sender.send(sendPackage, incoming->src);
      } else if (incoming->protocol == PROTOCOL_PINGREPLY && incoming->dest == TOS_NODE_ID) {
         addOrRefreshNeighbor(incoming->src);
         // dbg(NEIGHBOR_CHANNEL, "Node %d refreshed neighbor %d\n", TOS_NODE_ID, incoming->src);
      }
      return msg;
   }

   command void NeighborDiscovery.printNeighbors(){

      uint16_t i;

      for(i = 0; i < neighborCount; i++){
         dbg(NEIGHBOR_CHANNEL, "Printing Neighbor: %d\n", neighbors[i]);
      }

   }

}
