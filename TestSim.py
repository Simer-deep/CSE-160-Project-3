from __future__ import print_function

import os
import struct
import sys
from TOSSIM import Tossim
from CommandMsg import CommandMsg


class TestSim:
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP = 3

    COMMAND_CHANNEL = "command"
    GENERAL_CHANNEL = "general"
    NEIGHBOR_CHANNEL = "neighbor"
    FLOODING_CHANNEL = "flooding"
    ROUTING_CHANNEL = "routing"
    TRANSPORT_CHANNEL = "transport"
    HASHMAP_CHANNEL = "hashmap"

    def __init__(self, seed=1):
        self.t = Tossim([])
        self.t.randomSeed(seed)
        self.r = self.t.radio()
        self.moteids = []
        self.numMote = 0
        self.links = {}
        self.injected = []
        self.base = os.path.dirname(os.path.abspath(__file__))
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    def loadTopo(self, topoFile):
        with open(os.path.join(self.base, "topo", topoFile)) as topology:
            self.numMote = int(topology.readline())
            for line in topology:
                if not line.strip():
                    continue
                source, destination, gain = line.split()
                source, destination, gain = int(source), int(destination), float(gain)
                self.links[source, destination] = gain
                self.r.add(source, destination, gain)
        self.moteids = sorted(set(node for link in self.links for node in link))
        if len(self.moteids) != self.numMote:
            raise ValueError("Topology node count does not match its links")

    def loadNoise(self, noiseFile):
        if not self.moteids:
            raise ValueError("Load a topology before noise")
        with open(os.path.join(self.base, "noise", noiseFile)) as noise:
            readings = [int(line.strip()) for line in noise if line.strip()]
        if not readings:
            raise ValueError("Noise file is empty")
        for node in self.moteids:
            mote = self.t.getNode(node)
            for reading in readings:
                mote.addNoiseTraceReading(reading)
            mote.createNoiseModel()

    def bootNode(self, nodeID):
        if nodeID not in self.moteids:
            raise ValueError("Node is not in the topology")
        self.t.getNode(nodeID).bootAtTime(1333 * nodeID)

    def bootAll(self):
        for node in self.moteids:
            self.bootNode(node)

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff()

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn()

    def removeLink(self, source, destination):
        self.r.remove(source, destination)
        self.r.remove(destination, source)

    def restoreLink(self, source, destination):
        self.r.add(source, destination, self.links[source, destination])
        self.r.add(destination, source, self.links[destination, source])

    def setGain(self, source, destination, gain):
        self.r.add(source, destination, gain)
        self.r.add(destination, source, gain)

    def seconds(self):
        return float(self.t.time()) / self.t.ticksPerSecond()

    def run(self, ticks):
        for unused in range(ticks):
            self.t.runNextEvent()

    def runTime(self, amount):
        if amount < 0:
            raise ValueError("Simulation duration must be nonnegative")
        end = self.t.time() + int(amount * self.t.ticksPerSecond())
        stalled = 0
        while self.t.time() < end:
            before = self.t.time()
            self.t.runNextEvent()
            stalled = stalled + 1 if self.t.time() == before else 0
            if stalled >= 1000:
                raise RuntimeError("Simulator stopped advancing time")

    def sendCMD(self, ID, dest, payloadStr):
        if len(payloadStr) >= 25:
            raise ValueError("Command payload must leave room for a terminator")
        self.msg.set_dest(dest)
        self.msg.set_id(ID)
        for index in range(25):
            self.msg.setElement_payload(index, 0)
        self.msg.setString_payload(payloadStr)
        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time() + 5)

    def ping(self, source, dest, msg):
        if not 0 <= dest <= 255:
            raise ValueError("Ping destination must fit in one byte")
        self.sendCMD(self.CMD_PING, source, chr(dest) + msg)

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command")

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command")

    def injectRaw(self, source, receiver, amType, data):
        packet = self.t.newPacket()
        packet.setSource(source)
        packet.setDestination(receiver)
        packet.setType(amType)
        packet.setData(data)
        packet.deliver(receiver, self.t.time() + 1)
        self.injected.append(packet)
        return packet

    def injectIP(self, source, dest, receiver, ttl, seq, payload="TTL"):
        if not isinstance(payload, bytes):
            payload = payload.encode("ascii")
        data = struct.pack("!HHHBB20s", dest, source, seq, ttl, 0, payload)
        return self.injectRaw(source, receiver, 9, data)

    def injectDV(self, source, receiver, entries):
        if len(entries) > 9:
            raise ValueError("A DV packet holds at most nine entries")
        body = struct.pack("B", len(entries))
        for destination, cost in entries:
            body += struct.pack("BB", destination, cost)
        data = struct.pack("!HHHBB", receiver, source, 0, 1, 5)
        return self.injectRaw(source, receiver, 8, data + body.ljust(20, b"\0"))

    def addChannel(self, channelName, out=sys.stdout):
        self.t.addChannel(channelName, out)


def main():
    from test_dv_line import main as run_line
    run_line()


if __name__ == '__main__':
    main()
