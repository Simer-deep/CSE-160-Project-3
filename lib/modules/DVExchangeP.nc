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

    uint16_t updateSequence = 0;
    uint16_t currentUpdateId = 0;

    uint8_t totalPackets = 0;
    uint8_t snapshotCount = 0;

    uint8_t snapshotDestinations[DV_MAX_ROUTES];
    uint8_t snapshotCosts[DV_MAX_ROUTES];
    uint16_t snapshotNextHops[DV_MAX_ROUTES];

    uint8_t neighborIndex = 0;
    uint16_t currentNeighbor = AM_BROADCAST_ADDR;
    uint16_t routeIndex = 0;

    typedef struct 
    {
        bool active;
        bool hasRetired;

        uint16_t neighbor;
        uint16_t updateId;
        uint16_t lastRetiredId;

        uint8_t totalPackets;
        uint8_t receivedMask;
        uint8_t lastPacketCount;

        uint8_t packetCounts[DV_MAX_PACKETS];

        uint32_t lastActivity;

        uint8_t destinations[DV_MAX_ROUTES];
        uint8_t costs[DV_MAX_ROUTES];

    } dv_reassembly_t;

    dv_reassembly_t incomingUpdates[DV_MAX_NEIGHBORS];

    command void DVExchange.start() {

        uint16_t delay;

        if(started) {
            return;
        }

        started = TRUE;

        delay = 5000 + (call Random.rand16() % 1000);

        call Timer.startOneShot(delay);
    }

    void expireIncompleteUpdates();

    event void Timer.fired() {

        uint16_t delay;

        expireIncompleteUpdates();

        dbg(ROUTING_CHANNEL, "Node %d timer fired\n", TOS_NODE_ID);

        call DVExchange.sendUpdate();

        delay = 5000 + (call Random.rand16() % 1000);

        call Timer.startOneShot(delay);
    }

    bool isNewerUpdate(uint16_t candidate, uint16_t reference)
    {
        uint16_t difference = candidate - reference;

        return difference != 0 && difference < 0x8000;
    }

    uint8_t findReassemblySlot(uint16_t neighbor)
    {
        uint8_t i;

        for(i = 0; i < DV_MAX_NEIGHBORS; i++)
        {
            if(incomingUpdates[i].active &&
            !call ND.isNeighbor(incomingUpdates[i].neighbor))
            {
                incomingUpdates[i].active = FALSE;
                incomingUpdates[i].receivedMask = 0;
            }

            if(incomingUpdates[i].active &&
            incomingUpdates[i].neighbor == neighbor)
            {
                return i;
            }
        }

        for(i = 0; i < DV_MAX_NEIGHBORS; i++)
        {
            if(!incomingUpdates[i].active)
            {
                memset(&incomingUpdates[i], 0,
                    sizeof(dv_reassembly_t));

                incomingUpdates[i].active = TRUE;
                incomingUpdates[i].neighbor = neighbor;

                return i;
            }
        }

        return 0xFF;
    }

    void expireIncompleteUpdates()
    {
        uint8_t i;
        uint32_t now;

        now = call Timer.getNow();

        for(i = 0; i < DV_MAX_NEIGHBORS; i++)
        {
            if(incomingUpdates[i].active &&
            incomingUpdates[i].receivedMask != 0 &&
            (uint32_t)(now - incomingUpdates[i].lastActivity)
                >= DV_REASSEMBLY_TIMEOUT)
            {
                dbg(ROUTING_CHANNEL,
                    "Node %d discarded incomplete update %d from Node %d\n",
                    TOS_NODE_ID,
                    incomingUpdates[i].updateId,
                    incomingUpdates[i].neighbor);

                incomingUpdates[i].lastRetiredId =
                    incomingUpdates[i].updateId;

                incomingUpdates[i].hasRetired = TRUE;
                incomingUpdates[i].receivedMask = 0;
                incomingUpdates[i].totalPackets = 0;
                incomingUpdates[i].lastPacketCount = 0;
            }
        }
    }
    
    void sendNextPacket() 
    {
        uint16_t i;
        uint16_t neighbor;

        uint8_t neighborCount;
        uint8_t entryCount;
        uint8_t packetIndex;
        uint8_t sendCost;

        pack outgoing;

        if(!sending) {
            return;
        }

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

            if(routeIndex >= snapshotCount) {
                neighborIndex++;
                routeIndex = 0;
                continue;
            }

            memset(&outgoing, 0, sizeof(outgoing));

            outgoing.src = TOS_NODE_ID;
            outgoing.dest = neighbor;
            outgoing.TTL = 1;
            outgoing.protocol = PROTOCOL_DV;

            outgoing.seq = currentUpdateId;

            packetIndex = routeIndex / DV_MAX_ENTRIES;

            outgoing.payload[1] = packetIndex;
            outgoing.payload[2] = totalPackets;

            entryCount = 0;

            for(i = routeIndex;
                i < snapshotCount &&
                entryCount < DV_MAX_ENTRIES;
                i++) {

                sendCost = snapshotCosts[i];

                if(snapshotDestinations[i] == TOS_NODE_ID) {
                    sendCost = 0;
                }
                else if(snapshotNextHops[i] == neighbor) {
                    sendCost = DV_INFINITY;
                }

                outgoing.payload[3 + entryCount * 2] =
                    snapshotDestinations[i];

                outgoing.payload[4 + entryCount * 2] =
                    sendCost;

                entryCount++;
            }

            if(entryCount == 0) {
                neighborIndex++;
                routeIndex = 0;
                continue;
            }

            outgoing.payload[0] = entryCount;

            if(call Sender.send(outgoing, neighbor) != SUCCESS) {

                dbg(ROUTING_CHANNEL,
                    "Node %d failed to queue DV packet for neighbor %d, retrying\n",
                    TOS_NODE_ID, neighbor);

                call SendTimer.startOneShot(250);
                return;
            }

            dbg(ROUTING_CHANNEL,
                "Node %d queued DV update %d packet %d/%d with %d routes for neighbor %d\n",
                TOS_NODE_ID,
                currentUpdateId,
                packetIndex + 1,
                totalPackets,
                entryCount,
                neighbor);

            routeIndex += entryCount;

            call SendTimer.startOneShot(150);
            return;
        }

        sending = FALSE;

        dbg(ROUTING_CHANNEL,
            "Node %d finished sending DV update %d\n",
            TOS_NODE_ID,
            currentUpdateId);
    }

    command void DVExchange.sendUpdate()
    {
        uint16_t i;
        uint16_t destination;
        uint16_t nextHop;
        uint8_t cost;
        uint8_t routeCount;

        if(sending) {
            return;
        }

        routeCount = call DV.count();

        snapshotCount = 0;

        for(i = 0; i < routeCount; i++) {

            if(call DV.entryAt(i, &destination, &cost, &nextHop)) {

                // Destination must fit in one byte
                if(destination > 255) {
                    continue;
                }

                if(cost > DV_INFINITY) {
                    cost = DV_INFINITY;
                }

                if(destination == TOS_NODE_ID) {
                    cost = 0;
                }

                snapshotDestinations[snapshotCount] =
                    (uint8_t)destination;

                snapshotCosts[snapshotCount] = cost;

                snapshotNextHops[snapshotCount] = nextHop;

                snapshotCount++;
            }
        }

        if(snapshotCount == 0) {
            return;
        }

        updateSequence++;
        currentUpdateId = updateSequence;

        totalPackets =
            (snapshotCount + DV_MAX_ENTRIES - 1) / DV_MAX_ENTRIES;

        sending = TRUE;

        neighborIndex = 0;
        currentNeighbor = AM_BROADCAST_ADDR;
        routeIndex = 0;

        dbg(ROUTING_CHANNEL,
            "Node %d starting DV update ID %d with %d routes in %d packets\n",
            TOS_NODE_ID,
            currentUpdateId,
            snapshotCount,
            totalPackets);

        sendNextPacket();
    }

    event void SendTimer.fired() {

        sendNextPacket();
    }

    
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
    {
        uint16_t i;
        uint16_t destination;
        uint16_t neighbor;

        uint8_t cost;
        uint8_t count;
        uint8_t packetIndex;
        uint8_t totalPackets;

        uint8_t slotIndex;
        uint8_t packetBit;
        uint8_t completeMask;
        uint8_t offset;
        uint8_t totalEntries;

        uint32_t now;

        pack* incoming;
        dv_reassembly_t* update;

        // 1. Validate packet length
        if(len != sizeof(pack)) {
            return msg;
        }

        incoming = (pack*)payload;

        // 2. Validate protocol and destination
        if(incoming->protocol != PROTOCOL_DV ||
        incoming->dest != TOS_NODE_ID) {
            return msg;
        }

        // 3. Identify and validate sender
        neighbor = call AMPacket.source(msg);

        if(!call ND.isNeighbor(neighbor)) {
            dbg(ROUTING_CHANNEL,
                "Received DV packet from non-neighbor %d\n",
                neighbor);
            return msg;
        }

        // 4. Read packet metadata
        count = incoming->payload[0];
        packetIndex = incoming->payload[1];
        totalPackets = incoming->payload[2];

        // 5. Validate packet metadata
        if(count == 0 ||
        count > DV_MAX_ENTRIES ||
        totalPackets == 0 ||
        totalPackets > DV_MAX_PACKETS ||
        packetIndex >= totalPackets) {

            dbg(ROUTING_CHANNEL,
                "Node %d received invalid DV packet metadata\n",
                TOS_NODE_ID);

            return msg;
        }

        // Every packet except the final one must be full
        if(packetIndex < totalPackets - 1 &&
        count != DV_MAX_ENTRIES) {

            dbg(ROUTING_CHANNEL,
                "Node %d received incomplete DV packet\n",
                TOS_NODE_ID);

            return msg;
        }

        // 6. Validate every advertised entry before storing
        for(i = 0; i < count; i++) {

            cost = incoming->payload[4 + i * 2];

            if(cost > DV_INFINITY) {

                dbg(ROUTING_CHANNEL,
                    "Node %d received invalid DV cost\n",
                    TOS_NODE_ID);

                return msg;
            }
        }

        // 7. Find temporary storage for this neighbor
        slotIndex = findReassemblySlot(neighbor);

        if(slotIndex == 0xFF) {

            dbg(ROUTING_CHANNEL,
                "Node %d has no DV reassembly slot\n",
                TOS_NODE_ID);

            return msg;
        }

        update = &incomingUpdates[slotIndex];

        now = call Timer.getNow();

        // 8. Discard an expired incomplete advertisement
        if(update->receivedMask != 0 &&
        (uint32_t)(now - update->lastActivity)
            >= DV_REASSEMBLY_TIMEOUT) {

            update->lastRetiredId = update->updateId;
            update->hasRetired = TRUE;

            update->receivedMask = 0;
            update->totalPackets = 0;
            update->lastPacketCount = 0;
        }

        // 9. Handle packets belonging to different advertisements
        if(update->receivedMask != 0 &&
        update->updateId != incoming->seq) {

            if(!isNewerUpdate(incoming->seq,
                            update->updateId)) {
                return msg;
            }

            update->receivedMask = 0;
            update->totalPackets = 0;
            update->lastPacketCount = 0;
        }

        // 10. Start collecting a new advertisement
        if(update->receivedMask == 0) {

            if(update->hasRetired &&
            !isNewerUpdate(incoming->seq,
                            update->lastRetiredId)) {
                return msg;
            }

            update->updateId = incoming->seq;
            update->totalPackets = totalPackets;
        }

        else if(update->totalPackets != totalPackets) {

            // Conflicting metadata: discard the entire update
            update->lastRetiredId = update->updateId;
            update->hasRetired = TRUE;

            update->receivedMask = 0;
            update->totalPackets = 0;

            return msg;
        }

        // 11. Identify this packet using its bit
        packetBit = (uint8_t)(1 << packetIndex);

        offset = packetIndex * DV_MAX_ENTRIES;

        if(update->receivedMask & packetBit) {

        if(update->packetCounts[packetIndex] != count) {

            update->lastRetiredId = update->updateId;
            update->hasRetired = TRUE;

            update->receivedMask = 0;
            update->totalPackets = 0;

            return msg;
        }

        for(i = 0; i < count; i++) {

            if(update->destinations[offset + i] !=
                incoming->payload[3 + i * 2] ||
            update->costs[offset + i] !=
                incoming->payload[4 + i * 2]) {

                update->lastRetiredId = update->updateId;
                update->hasRetired = TRUE;

                update->receivedMask = 0;
                update->totalPackets = 0;

                return msg;
            }
        }

        return msg;
    }

        // 13. Store entries in temporary memory
        for(i = 0; i < count; i++) {

            update->destinations[offset + i] =
                incoming->payload[3 + i * 2];

            update->costs[offset + i] =
                incoming->payload[4 + i * 2];
        }

        update->packetCounts[packetIndex] = count;

        if(packetIndex == totalPackets - 1) {
            update->lastPacketCount = count;
        }

        update->lastActivity = now;

        // 14. Mark this packet as received
        update->receivedMask |= packetBit;

        completeMask =
            (uint8_t)((1 << totalPackets) - 1);

        // 15. Wait until every packet arrives
        if(update->receivedMask != completeMask) {

            dbg(ROUTING_CHANNEL,
                "Node %d received packet %d/%d from Node %d; waiting for remaining packets\n",
                TOS_NODE_ID,
                packetIndex + 1,
                totalPackets,
                neighbor);

            return msg;
        }

        // 16. Calculate total number of advertised entries
        totalEntries =
            (totalPackets - 1) * DV_MAX_ENTRIES +
            update->lastPacketCount;

        if(totalEntries == 0 ||
        totalEntries > DV_MAX_ROUTES) {

            update->lastRetiredId = update->updateId;
            update->hasRetired = TRUE;
            update->receivedMask = 0;
            update->totalPackets = 0;

            return msg;
        }

        dbg(ROUTING_CHANNEL,
            "Node %d received complete DV update %d from Node %d with %d entries\n",
            TOS_NODE_ID,
            update->updateId,
            neighbor,
            totalEntries);

        // 17. NOW update the routing table
        for(i = 0; i < totalEntries; i++) {

            destination = update->destinations[i];
            cost = update->costs[i];

            call DV.acceptEntry(
                neighbor,
                destination,
                cost
            );

            dbg(ROUTING_CHANNEL,
                "Node %d received from neighbor %d: Dest %d Cost %d\n",
                TOS_NODE_ID,
                neighbor,
                destination,
                cost);
        }

        // 18. Remember this completed advertisement
        update->lastRetiredId = update->updateId;
        update->hasRetired = TRUE;

        update->receivedMask = 0;
        update->totalPackets = 0;
        update->lastPacketCount = 0;

        return msg;
    }

}
