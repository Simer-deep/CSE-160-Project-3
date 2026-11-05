from __future__ import print_function

import os
import re

from TestSim import TestSim


class DVTest(object):
    def __init__(self, name, topology, noise="no_noise.txt"):
        self.name = name
        root = os.path.dirname(os.path.abspath(__file__))
        directory = os.path.join(root, "logs")
        if not os.path.isdir(directory):
            os.makedirs(directory)
        self.path = os.path.join(directory, name + ".log")
        self.log = open(self.path, "w+")
        self.s = TestSim(seed=1)
        self.phase("seed=1 topology=topo/%s noise=noise/%s" % (topology, noise))
        self.s.loadTopo(topology)
        self.s.loadNoise(noise)
        for channel in (self.s.COMMAND_CHANNEL, self.s.GENERAL_CHANNEL,
                        self.s.ROUTING_CHANNEL, self.s.NEIGHBOR_CHANNEL,
                        self.s.FLOODING_CHANNEL):
            self.s.addChannel(channel, self.log)
        with open(os.path.join(root, "topo", topology)) as topology_file:
            self.phase("directed links: " + "; ".join(topology_file.read().splitlines()[1:]))
        self.phase("boot nodes %s at ticks 1333 * ID; ticks/second=%d" %
                   (sorted(self.s.moteids), self.s.t.ticksPerSecond()))
        self.s.bootAll()

    def phase(self, message):
        line = "TEST %.6fs %s" % (self.s.seconds(), message)
        print(line)
        self.log.write(line + "\n")
        self.log.flush()

    def mark(self):
        self.log.flush()
        self.log.seek(0, os.SEEK_END)
        return self.log.tell()

    def read(self, start=0):
        self.log.flush()
        self.log.seek(start)
        text = self.log.read()
        self.log.seek(0, os.SEEK_END)
        return text

    def check(self, condition, message):
        self.phase(("PASS " if condition else "FAIL ") + message)
        if not condition:
            raise AssertionError(message + "; see " + self.path)

    def wait(self, seconds, reason):
        self.phase("wait %gs: %s" % (seconds, reason))
        self.s.runTime(seconds)
        self.phase("finished waiting")

    def table(self, node):
        self.phase("command routeDMP(%d)" % node)
        start = self.mark()
        self.s.routeDMP(node)
        self.s.runTime(1)
        text = self.read(start)
        self.check("Node %d Routing Table" % node in text, "node %d printed its table" % node)
        rows = {}
        pattern = r"DEBUG\s*\(\s*(\d+)\s*\):\s*(\d+)\s+(NONE|\d+)\s+(INF|\d+)\s+([A-Z_]+)\b"
        for owner, destination, next_hop, cost, state in re.findall(pattern, text):
            if int(owner) == node:
                rows[int(destination)] = (None if next_hop == "NONE" else int(next_hop),
                                          16 if cost == "INF" else int(cost), state)
        self.check(bool(rows), "node %d printed route entries" % node)
        return rows

    def route(self, node, destination, next_hop, cost):
        actual = self.table(node).get(destination)
        expected = (next_hop, cost, "VALID")
        self.check(actual == expected, "%d -> %d expected %s, got %s" %
                   (node, destination, expected, actual))

    def unreachable(self, node, destination):
        actual = self.table(node).get(destination)
        self.check(actual is None or (actual[0] is None and actual[1] == 16 and actual[2] != "VALID"),
                   "%d -> %d has no route; got %s" % (node, destination, actual))

    def ping(self, source, destination, path, seconds=10):
        reply_path = list(reversed(path))
        self.phase("command ping(%d, %d); expected paths %s and %s" %
                   (source, destination, path, reply_path))
        start = self.mark()
        self.s.ping(source, destination, "DV test")
        self.s.runTime(seconds)
        text = self.read(start)
        pattern = (r"Node (\d+) Routing Packet - src: (\d+), dest: (\d+), seq: (\d+), "
                   r"next hop: (\d+), cost: (\d+), TTL: (\d+)")
        sends = [tuple(map(int, event)) for event in re.findall(pattern, text)]
        originals = [event for event in sends if event[:3] == (source, source, destination)]
        self.check(bool(originals), "source queued the ping")
        sequence = originals[0][3]
        forward = [event for event in sends if event[1:4] == (source, destination, sequence)]
        reverse = [event for event in sends if event[1:4] == (destination, source, sequence)]
        for label, events, expected in (("ping", forward, path), ("reply", reverse, reply_path)):
            hops = len(expected) - 1
            self.check([event[0] for event in events] == expected[:-1],
                       "%s followed %s" % (label, expected[:-1]))
            self.check([event[4] for event in events] == expected[1:],
                       "%s used the expected next hops" % label)
            self.check([event[5] for event in events] == list(range(hops, 0, -1)),
                       "%s used the expected route costs" % label)
            self.check([event[6] for event in events] == list(range(32, 32 - hops, -1)),
                       "%s decreased TTL once at each relay" % label)
        self.check("Node %d received PING from Node %d, seq: %d" % (destination, source, sequence) in text,
                   "destination received the routed ping")
        self.check("Node %d received PING REPLY from Node %d, seq: %d" % (source, destination, sequence) in text,
                   "source received the reply for this ping")

    def dropped_ping(self, source, destination):
        self.phase("command ping(%d, %d); expected no-route drop" % (source, destination))
        start = self.mark()
        self.s.ping(source, destination, "unreachable")
        self.s.runTime(5)
        text = self.read(start)
        self.check("Node %d has no route to %d" % (source, destination) in text,
                   "ping was dropped because there was no route")
        self.check("Routing Packet - src: %d, dest: %d," % (source, destination) not in text,
                   "unreachable ping was not sent")
        self.check("received PING REPLY" not in text, "no reply for the unreachable ping")

    def finish(self):
        self.check("received src=" not in self.read(), "ping and reply did not use flooding")
        self.phase(self.name + " finished; all checks passed")
