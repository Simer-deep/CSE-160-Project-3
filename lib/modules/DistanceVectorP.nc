#include "../../includes/dv.h"
#include <Timer.h>

module DistanceVectorP 
{
    provides interface DistanceVector;
    uses interface NeighborDiscovery as ND;
    uses interface Timer<TMilli> as MaintenanceTimer;
}

implementation 
{
    dv_route_t routingTable[DV_MAX_ROUTES];

    uint8_t routeCount = 0;

    bool initialized = FALSE;

    void initializeRoutes() 
    {
        if (initialized) 
        {
            return;
        }

        routingTable[0].destination = TOS_NODE_ID;
        routingTable[0].nextHop = TOS_NODE_ID;
        routingTable[0].cost = 0;
        routingTable[0].state = DV_ROUTE_VALID;

        routeCount = 1;
        initialized = TRUE;
    }

    command uint8_t DistanceVector.count() 
    {
        return routeCount;
    }

        
    void addDirectNeighbor(uint16_t neighborId) 
    {
        uint8_t i;

        for (i = 0; i < routeCount; i++) 
        {
            if (routingTable[i].destination == neighborId) 
            {
                routingTable[i].nextHop = neighborId;
                routingTable[i].cost = 1;
                routingTable[i].state = DV_ROUTE_VALID;
                routingTable[i].lastUpdated = call MaintenanceTimer.getNow();
                return;
            }
        }

        if (routeCount >= DV_MAX_ROUTES)
        {
            return;
        }

        routingTable[routeCount].destination = neighborId;
        routingTable[routeCount].nextHop = neighborId;
        routingTable[routeCount].cost = 1;
        routingTable[routeCount].state = DV_ROUTE_VALID;
        routingTable[routeCount].lastUpdated = call MaintenanceTimer.getNow();

        routeCount++;
    }


    command void DistanceVector.start() 
    {
        uint8_t i;
        uint8_t neighborCount;
        uint16_t neighborId;

        initializeRoutes();

        neighborCount = call ND.getNeighborCount();

        for (i = 0; i < neighborCount; i++) 
        {
            if (call ND.getNeighborAt(i, &neighborId)) 
            {
                addDirectNeighbor(neighborId);
                dbg(ROUTING_CHANNEL,
                    "Node %d found neighbor %d\n",
                    TOS_NODE_ID, neighborId);
            }
        }

        call MaintenanceTimer.startPeriodic(1000);
    }

    void withdrawRoute(uint8_t i) 
    {
        if (routingTable[i].state != DV_ROUTE_WITHDRAWN) 
        {
            routingTable[i].lastUpdated = call MaintenanceTimer.getNow();
        }

        routingTable[i].cost = DV_INFINITY;
        routingTable[i].nextHop = DV_NO_NEXT_HOP;
        routingTable[i].state = DV_ROUTE_WITHDRAWN;
    }

   event void MaintenanceTimer.fired() 
   {
        uint8_t i;
        uint8_t neighborCount;
        uint16_t neighborId;

        neighborCount = call ND.getNeighborCount();

        for (i = 0; i < neighborCount; i++) 
        {
            if (call ND.getNeighborAt(i, &neighborId)) 
            {
                addDirectNeighbor(neighborId);
            }
        }

        
        for (i = 0; i < routeCount; i++) 
        {
            if (routingTable[i].destination == TOS_NODE_ID) 
            {
                continue;
            }

            if (routingTable[i].state == DV_ROUTE_VALID &&
                !call ND.isNeighbor(routingTable[i].nextHop)) 
                {

                dbg(ROUTING_CHANNEL,
                    "Node %d lost route to %d via %d\n",
                    TOS_NODE_ID,
                    routingTable[i].destination,
                    routingTable[i].nextHop);

                withdrawRoute(i);
            }
        }

        for (i = 0; i < routeCount; i++) 
        {
            if (routingTable[i].destination == TOS_NODE_ID ||
                routingTable[i].state != DV_ROUTE_VALID) 
                {
                    continue;
                }

            if (routingTable[i].destination ==
                    routingTable[i].nextHop &&
                call ND.isNeighbor(routingTable[i].destination)) 
                {
                    continue;
                }

            if ((uint32_t)(call MaintenanceTimer.getNow() -
                routingTable[i].lastUpdated) >= DV_ROUTE_TIMEOUT) 
                {

                    dbg(ROUTING_CHANNEL,
                        "Node %d route to %d expired\n",
                        TOS_NODE_ID,
                        routingTable[i].destination);

                    withdrawRoute(i);
                }
        }

                
        for (i = 1; i < routeCount; ) 
        {
            if (routingTable[i].state == DV_ROUTE_WITHDRAWN &&
                (uint32_t)(call MaintenanceTimer.getNow() -
                routingTable[i].lastUpdated) >= DV_WITHDRAW_TIMEOUT) 
                {
                    uint8_t j;

                    for (j = i; j + 1 < routeCount; j++) 
                    {
                        routingTable[j] = routingTable[j + 1];
                    }

                    routeCount--;
                } 
            
            else 
            {
                i++;
            }
        }
    }

    command bool DistanceVector.entryAt(
        uint8_t index,
        uint16_t* destination,
        uint8_t* cost,
        uint16_t* nextHop
    ) 
    {
        if (index >= routeCount ||
            destination == NULL ||
            cost == NULL ||
            nextHop == NULL) 
            {
                return FALSE;
            }

        *destination = routingTable[index].destination;
        *cost = routingTable[index].cost;
        *nextHop = routingTable[index].nextHop;

        return TRUE;
    }
    
    command bool DistanceVector.lookup(
        uint16_t destination,
        uint16_t* nextHop,
        uint8_t* cost
    ) {
        uint8_t i;

        if (nextHop == NULL || cost == NULL) 
        {
            return FALSE;
        }

        for (i = 0; i < routeCount; i++) 
        {
            if (routingTable[i].destination == destination &&
                routingTable[i].state == DV_ROUTE_VALID &&
                routingTable[i].cost < DV_INFINITY) 
                {

                    *nextHop = routingTable[i].nextHop;
                    *cost = routingTable[i].cost;

                    return TRUE;
                }
        }

        return FALSE;
    }

    command void DistanceVector.printTable() 
    {
        uint8_t i;

        dbg(ROUTING_CHANNEL,
            "Node %d Routing Table\n", TOS_NODE_ID);

        dbg(ROUTING_CHANNEL,
            "Dest NextHop Cost State\n");

        for (i = 0; i < routeCount; i++) 
        {
            dv_route_t* route = &routingTable[i];

            if (route->state == DV_ROUTE_VALID &&
                route->cost < DV_INFINITY) 
                {
                    dbg(ROUTING_CHANNEL,
                        "%d %d %d VALID\n",
                        route->destination,
                        route->nextHop,
                        route->cost);
                }
            else if (route->state == DV_ROUTE_WITHDRAWN) 
            {

                dbg(ROUTING_CHANNEL,
                    "%d NONE INF WITHDRAWN\n",
                    route->destination);
            }
        }
    }

    
    command void DistanceVector.acceptEntry(
        uint16_t from,
        uint16_t destination,
        uint8_t cost
    ) {
        uint8_t newCost;
        uint8_t i;

        if (!call ND.isNeighbor(from))
        {
            return;
        }

        if (destination == TOS_NODE_ID) 
        {
            return;
        }

        if (call ND.isNeighbor(destination)) 
        {
            return;
        }

        if (cost >= DV_INFINITY) 
        {
            newCost = DV_INFINITY;
        }

        else 
        {
            newCost = cost + 1;
        }

        for (i = 0; i < routeCount; i++) 
        {
            if (routingTable[i].destination == destination) 
            {
                break;
            }
        }

        if (i == routeCount) 
        {
            if (newCost == DV_INFINITY ||
                routeCount >= DV_MAX_ROUTES) 
                {
                    return;
                }

            routingTable[i].destination = destination;
            routingTable[i].nextHop = from;
            routingTable[i].cost = newCost;
            routingTable[i].state = DV_ROUTE_VALID;

            routingTable[i].lastUpdated = call MaintenanceTimer.getNow();

            routeCount++;
            return;
        }

        if (routingTable[i].nextHop == from ||
            (routingTable[i].state != DV_ROUTE_VALID &&
            newCost < DV_INFINITY) ||
            newCost < routingTable[i].cost) 
            {
                routingTable[i].cost = newCost;

                if (newCost == DV_INFINITY) 
                {
                    withdrawRoute(i);
                } 
                else 
                {
                    if (routingTable[i].state == DV_ROUTE_WITHDRAWN)
                    {
                        dbg(ROUTING_CHANNEL,
                            "Node %d recovered route to %d via %d cost %d\n",
                            TOS_NODE_ID,
                            destination,
                            from,
                            newCost);
                    }
                    
                    routingTable[i].nextHop = from;
                    routingTable[i].cost = newCost;
                    routingTable[i].state = DV_ROUTE_VALID;
                }

                if (newCost < DV_INFINITY) 
                {
                    routingTable[i].lastUpdated = call MaintenanceTimer.getNow();
                }
            }
    }
}
