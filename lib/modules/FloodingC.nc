#include "../../includes/packet.h"

configuration FloodingC {
   provides interface Flooding;
}
implementation {
   components FloodingP;
   components new AMReceiverC(AM_PACK) as Receiver;
   components new SimpleSendC(AM_PACK) as Sender;

   Flooding = FloodingP.Flooding;
   FloodingP.Receive -> Receiver.Receive;
   FloodingP.Sender -> Sender.SimpleSend;
}
