/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

configuration NodeC {
}
implementation {
   components MainC, Node, ActiveMessageC, CommandHandlerC;
   components NeighborDiscoveryC, FloodingC;
   components DVExchangeC;
   components DistanceVectorC;
   components IPRoutingC;

   Node.Boot -> MainC.Boot;
   Node.AMControl -> ActiveMessageC.SplitControl;
   Node.CommandHandler -> CommandHandlerC.CommandHandler;
   Node.NeighborDiscovery -> NeighborDiscoveryC.NeighborDiscovery;
   Node.Flooding -> FloodingC.Flooding;

   Node.DVExchange -> DVExchangeC.DVExchange;
   DVExchangeC.DV -> DistanceVectorC.DistanceVector;
   DVExchangeC.ND -> NeighborDiscoveryC.NeighborDiscovery;

   Node.IPRouting -> IPRoutingC.IPRouting;
   IPRoutingC.DV -> DistanceVectorC.DistanceVector;
   IPRoutingC.ND -> NeighborDiscoveryC.NeighborDiscovery;
   Node.DV -> DistanceVectorC.DistanceVector;
}
