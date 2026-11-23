interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t port);
   event void setTestClient(uint16_t address, uint8_t srcPort,
       uint8_t destPort, uint32_t length);
   event void setTestExpected(uint16_t address, uint8_t srcPort,
       uint8_t destPort, uint32_t length);
   event void setTestClose(uint16_t address, uint8_t srcPort, uint8_t destPort);
   event void setTestPause(uint16_t address, uint8_t srcPort, uint8_t destPort);
   event void setTestResume(uint16_t address, uint8_t srcPort, uint8_t destPort);
   event void setTestDrop(uint16_t source, uint16_t destination,
       uint8_t srcPort, uint8_t destPort, uint8_t flags,
       uint16_t sequence, uint16_t acknowledgement,
       uint8_t windowMode, uint8_t count);
   event void setAppServer();
   event void setAppClient();
}
