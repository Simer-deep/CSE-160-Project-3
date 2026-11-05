interface NeighborDiscovery {
   command void start();
   command void printNeighbors();
   command bool isNeighbor(uint16_t nodeId);
   command uint8_t getNeighborCount();
   command bool getNeighborAt(uint8_t index, uint16_t *nodeId);
}
