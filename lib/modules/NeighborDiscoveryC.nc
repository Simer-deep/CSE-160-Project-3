#include <Timer.h>
#include "../../includes/am_types.h"

configuration NeighborDiscoveryC {
   provides interface NeighborDiscovery;
}
implementation {
   components NeighborDiscoveryP;
   components new TimerMilliC() as NeighborTimer;
   components RandomC;
   components new AMReceiverC(AM_NEIGHBOR_DISCOVERY) as Receiver;
   components new SimpleSendC(AM_NEIGHBOR_DISCOVERY) as Sender;

   NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;
   NeighborDiscoveryP.NeighborTimer -> NeighborTimer.Timer;
   NeighborDiscoveryP.Random -> RandomC.Random;
   NeighborDiscoveryP.Receive -> Receiver.Receive;
   NeighborDiscoveryP.Sender -> Sender.SimpleSend;
}
