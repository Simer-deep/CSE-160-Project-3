#include "../../includes/am_types.h"

configuration IPRoutingC {

    provides interface IPRouting;

    uses interface DistanceVector as DV;
    uses interface NeighborDiscovery as ND;
}

implementation {

    components IPRoutingP;

    components new AMReceiverC(AM_IP) as Receiver;
    components new SimpleSendC(AM_IP) as Sender;

    IPRouting = IPRoutingP.IPRouting;

    IPRoutingP.Receive -> Receiver.Receive;
    IPRoutingP.Sender -> Sender.SimpleSend;

    DV = IPRoutingP.DV;
    ND = IPRoutingP.ND;
}
