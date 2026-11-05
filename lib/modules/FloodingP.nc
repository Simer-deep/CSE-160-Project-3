#include "../../includes/packet.h"
#include "../../includes/channels.h"

module FloodingP {
   provides interface Flooding;
   uses interface Receive;
   uses interface SimpleSend as Sender;
}
implementation {
   pack sendPackage;
   uint16_t sequenceNum = 0; //Sequence incr++
   uint16_t seenSrc[15];
   uint16_t seenSeq[15];
   uint16_t Scount = 0;
   uint16_t Snext = 0;

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, const void* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   void rememberPacket(uint16_t src, uint16_t seq)
   {
      seenSrc[Snext] = src;
      seenSeq[Snext] = seq;

      Snext = (Snext + 1) % 15;

      if(Scount < 15)
      {
         Scount++;
      }
   }


   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

      uint16_t i;
      pack forwardPackage;

      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){ //take all information and fill it in to the flooding channel
         pack* myMsg=(pack*) payload;
         dbg(FLOODING_CHANNEL,
            "Node %d received src=%d dest=%d seq=%d TTL=%d protocol=%d payload=%.*s\n",
            TOS_NODE_ID,
            myMsg->src,
            myMsg->dest,
            myMsg->seq,
            myMsg->TTL,
            myMsg->protocol,
            PACKET_MAX_PAYLOAD_SIZE,
            myMsg->payload
         );

         for(i = 0; i < Scount; i++)
         {
            if(seenSrc[i] == myMsg->src && seenSeq[i] == myMsg->seq)
            {
               return msg;
            }
         }

         rememberPacket(myMsg->src, myMsg->seq);

         if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) // Is this for me and protocol is ping. If yes then send back as protocol reply
            {

               makePack(
                  &sendPackage, 
                  TOS_NODE_ID, 
                  myMsg->src, 
                  MAX_TTL, 
                  PROTOCOL_PINGREPLY, 
                  sequenceNum, 
                  myMsg->payload, 
                  PACKET_MAX_PAYLOAD_SIZE
               );
               rememberPacket(TOS_NODE_ID, sequenceNum);

               sequenceNum++; 
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);
            }

         if(myMsg->dest == TOS_NODE_ID){
            if(myMsg->protocol == PROTOCOL_PINGREPLY){
               dbg(GENERAL_CHANNEL, "Ping reply recieved from %d\n", myMsg->src);
            }

            return msg;
         }

         if(myMsg->TTL == 0){ //if time to live goes to 0 we drop msg
            return msg;
         }

         forwardPackage = *myMsg;
         forwardPackage.TTL = myMsg->TTL - 1;

         call Sender.send(forwardPackage, AM_BROADCAST_ADDR);

         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }



   command error_t Flooding.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      
      makePack(
         &sendPackage, 
         TOS_NODE_ID, 
         destination, 
         MAX_TTL, 
         PROTOCOL_PING, 
         sequenceNum, 
         payload, 
         PACKET_MAX_PAYLOAD_SIZE
      );

      rememberPacket(TOS_NODE_ID, sequenceNum);

      sequenceNum++; 
      return call Sender.send(sendPackage, AM_BROADCAST_ADDR); // Send this radio frame to every node that is physically one hop away from me (AM_BORADCAST).
   }

}
