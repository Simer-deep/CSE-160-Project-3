configuration DistanceVectorC {
    provides interface DistanceVector;
}

implementation {
    components DistanceVectorP;
    components NeighborDiscoveryC;
    components new TimerMilliC() as MaintenanceTimer;

    DistanceVector = DistanceVectorP.DistanceVector;
    
    DistanceVectorP.ND -> NeighborDiscoveryC.NeighborDiscovery;
    DistanceVectorP.MaintenanceTimer -> MaintenanceTimer;
}