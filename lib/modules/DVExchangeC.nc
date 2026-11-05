#include "../../includes/am_types.h"
#include <Timer.h>

configuration DVExchangeC {
    provides interface DVExchange;

    uses interface DistanceVector as DV;
    uses interface NeighborDiscovery as ND;
}

implementation {
    components DVExchangeP;
    components new TimerMilliC() as Timer;
    components new TimerMilliC() as SendTimer;
    components RandomC;

    components new AMReceiverC(AM_DV) as Receiver;
    components new SimpleSendC(AM_DV) as Sender;

    components ActiveMessageC;

    DVExchange = DVExchangeP.DVExchange;

    DVExchangeP.Receive -> Receiver.Receive;
    DVExchangeP.Sender -> Sender.SimpleSend;
    DVExchangeP.AMPacket -> ActiveMessageC.AMPacket;

    DV = DVExchangeP.DV;
    ND = DVExchangeP.ND;

    DVExchangeP.Timer -> Timer.Timer;
    DVExchangeP.SendTimer -> SendTimer.Timer;
    DVExchangeP.Random -> RandomC.Random;
}
