#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"
#include "../../includes/dv.h"
#include <string.h>
#include "../../includes/transport.h"

module IPRoutingP {

    provides interface IPRouting;

    uses interface Receive;
    uses interface SimpleSend as Sender;

    uses interface DistanceVector as DV;
    uses interface NeighborDiscovery as ND;
}

implementation {

    uint16_t sequenceNum = 0;
    bool dropActive = FALSE;
    uint16_t dropSource;
    uint16_t dropDestination;
    uint8_t dropSrcPort;
    uint8_t dropDestPort;
    uint8_t dropFlags;
    uint16_t dropSequence;
    uint16_t dropAcknowledgement;
    uint8_t dropWindowMode;
    uint8_t dropCount;

    command void IPRouting.setTestDrop(uint16_t source, uint16_t destination,
        uint8_t srcPort, uint8_t destPort, uint8_t flags,
        uint16_t sequence, uint16_t acknowledgement,
        uint8_t windowMode, uint8_t count) {
        dropSource = source;
        dropDestination = destination;
        dropSrcPort = srcPort;
        dropDestPort = destPort;
        dropFlags = flags;
        dropSequence = sequence;
        dropAcknowledgement = acknowledgement;
        dropWindowMode = windowMode;
        dropCount = count;
        dropActive = count > 0;

        dbg("Project3TGen",
            "Node %u will drop transport traffic from %u to %u flags=%u\n",
            TOS_NODE_ID, source, destination, flags);
    }

    bool shouldDropForTest(pack* packet) {
        uint16_t sequence;
        uint16_t acknowledgement;
        uint8_t window;

        if(!dropActive || packet->protocol != PROTOCOL_TCP ||
            packet->dest == TOS_NODE_ID ||
            packet->src != dropSource || packet->dest != dropDestination ||
            packet->payload[0] != dropSrcPort ||
            packet->payload[1] != dropDestPort ||
            packet->payload[2] != dropFlags) {
            return FALSE;
        }

        sequence = ((uint16_t)packet->payload[3] << 8) | packet->payload[4];
        acknowledgement = ((uint16_t)packet->payload[5] << 8) |
            packet->payload[6];
        window = packet->payload[7];

        if((dropSequence != 65535U && sequence != dropSequence) ||
            (dropAcknowledgement != 65535U &&
                acknowledgement != dropAcknowledgement) ||
            (dropWindowMode == 1 && window != 0) ||
            (dropWindowMode == 2 && window == 0)) {
            return FALSE;
        }

        dropCount--;
        if(dropCount > 0) {
            return FALSE;
        }

        dropActive = FALSE;
        dbg("Project3TGen",
            "Node %u dropped transport packet from %u to %u flags=%u seq=%u ack=%u wnd=%u\n",
            TOS_NODE_ID, packet->src, packet->dest, packet->payload[2],
            sequence, acknowledgement, window);
        return TRUE;
    }

    command error_t IPRouting.sendTransport(
        uint16_t destination,
        uint8_t* payload,
        uint8_t length
    ) {
        pack outgoing;
        uint16_t nextHop;
        uint8_t cost;

        if (payload == NULL ||
            length < TRANSPORT_HEADER_SIZE ||
            length > PACKET_MAX_PAYLOAD_SIZE) {
            return FAIL;
        }

        if (destination == TOS_NODE_ID) {
            return FAIL;
        }

        if (!call DV.lookup(destination, &nextHop, &cost)) {
            dbg(ROUTING_CHANNEL,
                "Node %d: No TCP route to %d\n",
                TOS_NODE_ID, destination);
            return FAIL;
        }

        if (cost >= DV_INFINITY ||
            !call ND.isNeighbor(nextHop)) {
            return FAIL;
        }

        memset(&outgoing, 0, sizeof(pack));

        outgoing.src = TOS_NODE_ID;
        outgoing.dest = destination;
        outgoing.seq = sequenceNum++;
        outgoing.TTL = MAX_TTL;
        outgoing.protocol = PROTOCOL_TCP;

        memcpy(outgoing.payload, payload, length);

        if (call Sender.send(outgoing, nextHop) != SUCCESS) {
            dbg(ROUTING_CHANNEL,
                "Node %d: TCP packet queue failed\n",
                TOS_NODE_ID);
            return FAIL;
        }

        dbg(ROUTING_CHANNEL,
            "Node %d TCP packet sent to %d via %d\n",
            TOS_NODE_ID, destination, nextHop);

        return SUCCESS;
    }

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

        if(shouldDropForTest(incoming)) {
            return msg;
        }

        if(incoming->protocol != PROTOCOL_PING &&
        incoming->protocol != PROTOCOL_PINGREPLY &&
        incoming->protocol != PROTOCOL_TCP) 
        {
            return msg;
        }

        if(incoming->TTL == 0) {
            dbg(ROUTING_CHANNEL,
                "Node %d dropped packet because TTL expired - src: %d, dest: %d, seq: %d, TTL: %d\n",
                TOS_NODE_ID, incoming->src, incoming->dest,
                incoming->seq, incoming->TTL);
            return msg;
        }

        
    if(incoming->dest == TOS_NODE_ID) 
    {
        if(incoming->protocol == PROTOCOL_TCP) 
        {
            dbg(TRANSPORT_CHANNEL,
                "Node %d received TCP packet from Node %d, seq: %d\n",
                TOS_NODE_ID, incoming->src, incoming->seq);

            signal IPRouting.transportReceived(incoming);

        } 
        
        else if(incoming->protocol == PROTOCOL_PING) 
        {
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
                    
            } 
            else 
            {
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
