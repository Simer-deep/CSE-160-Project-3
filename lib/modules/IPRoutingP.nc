#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"
#include "../../includes/dv.h"
#include <string.h>

module IPRoutingP {

    provides interface IPRouting;

    uses interface Receive;
    uses interface SimpleSend as Sender;

    uses interface DistanceVector as DV;
    uses interface NeighborDiscovery as ND;
}

implementation {


    uint16_t sequenceNum = 0;

    command void IPRouting.ping(uint16_t destination, uint8_t* payload) {

        pack outgoing;
        uint16_t nextHop;
        uint8_t cost;

        if(destination == TOS_NODE_ID) {
            dbg(ROUTING_CHANNEL, "Node %d is already the destination\n", TOS_NODE_ID);
            return;
        }

        if(!call DV.lookup(destination, &nextHop, &cost)) {
            dbg(ROUTING_CHANNEL, "Node %d has no route to %d\n", TOS_NODE_ID, destination);
            return;
        }

        if(cost >= DV_INFINITY || !call ND.isNeighbor(nextHop)) {
            dbg(ROUTING_CHANNEL, "Node %d cannot reach %d\n", TOS_NODE_ID, destination);
            return;
        }

        memset(&outgoing, 0, sizeof(outgoing));

        outgoing.src = TOS_NODE_ID;
        outgoing.dest = destination;
        outgoing.seq = sequenceNum++;
        outgoing.TTL = MAX_TTL;
        outgoing.protocol = PROTOCOL_PING;

        if(payload != NULL) {
            memcpy(outgoing.payload, payload, PACKET_MAX_PAYLOAD_SIZE);
        }

        if(call Sender.send(outgoing, nextHop) != SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d failed to queue ping\n", TOS_NODE_ID);
            return;
        }

        dbg(ROUTING_CHANNEL,
            "Node %d Routing Packet - src: %d, dest: %d, seq: %d, next hop: %d, cost: %d, TTL: %d\n",
            TOS_NODE_ID, outgoing.src, outgoing.dest, outgoing.seq,
            nextHop, cost, outgoing.TTL);
    }

    
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {

        pack* incoming;

        if(len != sizeof(pack)) {
            return msg;
        }

        incoming = (pack*)payload;

        if(incoming->protocol != PROTOCOL_PING &&
        incoming->protocol != PROTOCOL_PINGREPLY) {
            return msg;
        }

        if(incoming->TTL == 0) {
            dbg(ROUTING_CHANNEL,
                "Node %d dropped packet because TTL expired - src: %d, dest: %d, seq: %d, TTL: %d\n",
                TOS_NODE_ID, incoming->src, incoming->dest,
                incoming->seq, incoming->TTL);
            return msg;
        }

        if(incoming->dest == TOS_NODE_ID) {

            
            if(incoming->protocol == PROTOCOL_PING) {

                pack reply;
                uint16_t nextHop;
                uint8_t cost;

                dbg(ROUTING_CHANNEL,
                    "Node %d received PING from Node %d, seq: %d\n",
                    TOS_NODE_ID, incoming->src, incoming->seq);

                if(!call DV.lookup(incoming->src, &nextHop, &cost)) {
                    dbg(ROUTING_CHANNEL, "No route back to %d\n", incoming->src);
                    return msg;
                }

                if(cost >= DV_INFINITY || !call ND.isNeighbor(nextHop)) {
                    dbg(ROUTING_CHANNEL, "Cannot send reply to %d\n", incoming->src);
                    return msg;
                }

                memcpy(&reply, incoming, sizeof(pack));

                reply.src = TOS_NODE_ID;
                reply.dest = incoming->src;
                reply.protocol = PROTOCOL_PINGREPLY;
                reply.TTL = MAX_TTL;

                if(call Sender.send(reply, nextHop) != SUCCESS) {
                    dbg(ROUTING_CHANNEL, "Failed to queue PINGREPLY\n");
                    return msg;
                }

                dbg(ROUTING_CHANNEL,
                    "Node %d Routing Packet - src: %d, dest: %d, seq: %d, next hop: %d, cost: %d, TTL: %d\n",
                    TOS_NODE_ID, reply.src, reply.dest, reply.seq,
                    nextHop, cost, reply.TTL);
                    
            } else {

                    dbg(ROUTING_CHANNEL,
                        "Node %d received PING REPLY from Node %d, seq: %d\n",
                        TOS_NODE_ID, incoming->src, incoming->seq);
                }

        } else {
            pack forwarded;
            uint16_t nextHop;
            uint8_t cost;

            if(incoming->TTL <= 1) {
                dbg(ROUTING_CHANNEL,
                    "Node %d dropped packet because TTL expired - src: %d, dest: %d, seq: %d, TTL: %d\n",
                    TOS_NODE_ID, incoming->src, incoming->dest,
                    incoming->seq, incoming->TTL);
                return msg;
            }

            if(!call DV.lookup(incoming->dest, &nextHop, &cost)) {
                dbg(ROUTING_CHANNEL,
                    "Node %d has no route to %d - src: %d, seq: %d\n",
                    TOS_NODE_ID, incoming->dest, incoming->src, incoming->seq);
                return msg;
            }

            if(cost >= DV_INFINITY || !call ND.isNeighbor(nextHop)) {
                dbg(ROUTING_CHANNEL,
                    "Node %d cannot forward to %d - src: %d, seq: %d\n",
                    TOS_NODE_ID, incoming->dest, incoming->src, incoming->seq);
                return msg;
            }

            memcpy(&forwarded, incoming, sizeof(pack));

            forwarded.TTL = incoming->TTL - 1;

            if(call Sender.send(forwarded, nextHop) != SUCCESS) {
                dbg(ROUTING_CHANNEL,
                    "Node %d failed to queue forwarded packet\n",
                    TOS_NODE_ID);
                return msg;
            }

            dbg(ROUTING_CHANNEL,
                "Node %d Routing Packet - src: %d, dest: %d, seq: %d, next hop: %d, cost: %d, TTL: %d\n",
                TOS_NODE_ID, forwarded.src, forwarded.dest, forwarded.seq,
                nextHop, cost, forwarded.TTL);

        }

        return msg;
    }


}
