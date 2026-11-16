configuration TransportTestC {
    provides interface TransportTest;
    uses interface Transport;
}

implementation {
    components TransportTestP;
    components new TimerMilliC() as TestTimer;

    TransportTest = TransportTestP.TransportTest;
    Transport = TransportTestP.Transport;
    TransportTestP.TestTimer -> TestTimer;
}
