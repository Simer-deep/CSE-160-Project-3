#include "../../includes/packet.h"
#include "../../includes/dv.h"
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include <Timer.h>
#include <string.h>

module DVExchangeP {
    provides interface DVExchange;

    uses interface Receive;
    uses interface AMPacket;
    uses interface SimpleSend as Sender;

    uses interface DistanceVector as DV;
    uses interface NeighborDiscovery as ND;

    uses interface Timer<TMilli> as Timer;
    uses interface Timer<TMilli> as SendTimer;
    uses interface Random as Random;
}

implementation {

    bool started = FALSE;
    bool sending = FALSE;

    uint8_t neighborIndex = 0;
    uint16_t currentNeighbor = AM_BROADCAST_ADDR;
    uint16_t routeIndex = 0;

    command void DVExchange.start() {

        uint16_t delay;

        if(started) {
            return;
        }

        started = TRUE;

        delay = 5000 + (call Random.rand16() % 1000);

        call Timer.startOneShot(delay);
    }

    event void Timer.fired() {

        uint16_t delay;

        dbg(ROUTING_CHANNEL, "Node %d timer fired\n", TOS_NODE_ID);

        call DVExchange.sendUpdate();

        delay = 5000 + (call Random.rand16() % 1000);

        call Timer.startOneShot(delay);
    }

    void sendNextPacket() {

        uint8_t routeCount;

        uint16_t i;
        uint16_t destination;
        uint8_t cost;
        uint16_t nextHop;

        uint8_t neighborCount;
        uint16_t neighbor;

        uint8_t sendCost;

        pack outgoing;
        uint8_t entryCount;

        if(!sending) {
            return;
        }

        routeCount = call DV.count();
        neighborCount = call ND.getNeighborCount();

        while(neighborIndex < neighborCount) {

            if(!call ND.getNeighborAt(neighborIndex, &neighbor)) {
                neighborIndex++;
                routeIndex = 0;
                continue;
            }

            if(neighbor != currentNeighbor) {
                currentNeighbor = neighbor;
                routeIndex = 0;
            }

            if(routeIndex >= routeCount) {
                neighborIndex++;
                routeIndex = 0;
                continue;
            }

            memset(&outgoing, 0, sizeof(outgoing));

            outgoing.src = TOS_NODE_ID;
            outgoing.dest = neighbor;
            outgoing.TTL = 1;
            outgoing.protocol = PROTOCOL_DV;
            outgoing.seq = 0;

            entryCount = 0;
            outgoing.payload[0] = 0;

            for(i = routeIndex; i < routeCount && entryCount < DV_MAX_ENTRIES; i++) {

                if(call DV.entryAt(i, &destination, &cost, &nextHop)) {

                    if(destination > 255) {
                        dbg(ROUTING_CHANNEL,
                            "Node %d cannot encode destination %d\n",
                            TOS_NODE_ID, destination);
                        continue;
                    }

                    sendCost = cost;

                    if(sendCost > DV_INFINITY) {
                        sendCost = DV_INFINITY;
                    }

                    if(destination == TOS_NODE_ID) {
                        sendCost = 0;
                    } else if(nextHop == neighbor) {
                        sendCost = DV_INFINITY;
                    }

                    outgoing.payload[1 + entryCount * 2] = (uint8_t)destination;
                    outgoing.payload[2 + entryCount * 2] = sendCost;

                    entryCount++;
                    outgoing.payload[0] = entryCount;

                }
            }

            if(entryCount == 0) {
                neighborIndex++;
                routeIndex = 0;
                continue;
            }

            if(call Sender.send(outgoing, neighbor) != SUCCESS) {

                dbg(ROUTING_CHANNEL,
                    "Node %d failed to queue DV packet for neighbor %d, retrying\n",
                    TOS_NODE_ID, neighbor);

                call SendTimer.startOneShot(250);
                return;
            }

            dbg(ROUTING_CHANNEL,
                "Node %d queued %d routes for neighbor %d starting at %d\n",
                TOS_NODE_ID, entryCount, neighbor, routeIndex);

            routeIndex = i;

            for(i = 0; i < entryCount; i++) {
                dbg(ROUTING_CHANNEL,
                    "Node %d to neighbor %d: Dest %d Advertised Cost %d\n",
                    TOS_NODE_ID, neighbor,
                    outgoing.payload[1 + i * 2], outgoing.payload[2 + i * 2]);
            }

            call SendTimer.startOneShot(150);
            return;
        }

        sending = FALSE;

        dbg(ROUTING_CHANNEL,
            "Node %d finished sending DV updates\n",
            TOS_NODE_ID);
    }

    command void DVExchange.sendUpdate() {

        if(sending) {
            return;
        }

        sending = TRUE;

        neighborIndex = 0;
        currentNeighbor = AM_BROADCAST_ADDR;
        routeIndex = 0;

        dbg(ROUTING_CHANNEL,
            "Node %d starting DV update\n",
            TOS_NODE_ID);

        sendNextPacket();
    }

    event void SendTimer.fired() {

        sendNextPacket();
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {

        uint16_t i;
        uint16_t destination;
        uint8_t cost;

        uint16_t neighbor;
        uint8_t count;

        pack* incoming;

        if(len != sizeof(pack)) {
            return msg;
        }

        incoming = (pack*) payload;

        if(incoming->protocol != PROTOCOL_DV || incoming->dest != TOS_NODE_ID) {
            return msg;
        }

        neighbor = call AMPacket.source(msg);

        if(!call ND.isNeighbor(neighbor)) {
            dbg(ROUTING_CHANNEL,
                "Received DV packet from non-neighbor %d\n",
                neighbor);
            return msg;
        }

        count = incoming->payload[0];

        if(count > DV_MAX_ENTRIES) {
            dbg(ROUTING_CHANNEL, "Invalid DV packet\n");
            return msg;
        }

        for(i = 0; i < count; i++) {

            cost = incoming->payload[2 + i * 2];

            if(cost > DV_INFINITY) {
                dbg(ROUTING_CHANNEL, "Invalid cost in DV packet\n");
                return msg;
            }
        }

        for(i = 0; i < count; i++) {

            destination = incoming->payload[1 + i * 2];
            cost = incoming->payload[2 + i * 2];

            call DV.acceptEntry(neighbor, destination, cost);

            dbg(ROUTING_CHANNEL,
                "Node %d received from neighbor %d: Dest %d Advertised Cost %d\n",
                TOS_NODE_ID, neighbor, destination, cost);
        }

        dbg(ROUTING_CHANNEL,
            "Node %d received a DV packet from Node %d\n",
            TOS_NODE_ID, neighbor);

        return msg;
    }
}
