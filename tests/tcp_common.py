from __future__ import print_function

import os
import re

from TestSim import TestSim

SERVER = 1
CLIENT = 4
SOURCE_PORT = 10
SERVER_PORT = 20
TRANSFER_BYTES = 1025

SYN = 1
ACK = 2
DATA = 8


class TestLog:
    def __init__(self, sim, output):
        self.sim = sim
        self.output = output
        self.newLine = True

    def write(self, message):
        for part in message.splitlines(True):
            if self.newLine:
                self.output.write("t=%.3f " % self.sim.seconds())
            self.output.write(part)
            self.newLine = part.endswith("\n")

    def flush(self):
        self.output.flush()


class TransportCase:
    def __init__(self, name, noise="no_noise.txt"):
        self.name = name
        folder = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        logFolder = os.path.join(folder, "logs")
        if not os.path.isdir(logFolder):
            os.makedirs(logFolder)
        self.path = os.path.join(logFolder, "tcp_%s.log" % name)
        self.output = open(self.path, "w")
        self.sim = TestSim(seed=1)
        self.sim.addChannel("Project3TGen", self.output)
        self.sim.addChannel("transport", self.output)
        self.sim.addChannel("routing", self.output)

        self.show("Loading tcp-line.topo and " + noise)
        self.sim.loadTopo("tcp-line.topo")
        self.sim.loadNoise(noise)
        self.sim.bootAll()
        self.show("Waiting 65 seconds for routing")
        self.sim.runTime(65)
        self.sim.ping(CLIENT, SERVER, "route")
        self.sim.runTime(3)

    def show(self, message):
        print("[%s] %s" % (self.name, message))

    def startServer(self):
        self.show("Starting server on node 1, port 20")
        self.sim.cmdTestServer(SERVER, SERVER_PORT)
        self.sim.runTime(2)

    def startClient(self):
        self.show("Starting 1025-byte transfer from node 4 to node 1")
        self.sim.cmdTestClient(CLIENT, SERVER, SOURCE_PORT,
                               SERVER_PORT, TRANSFER_BYTES)

    def drop(self, relay, source, destination, srcPort, destPort, flags,
             sequence=65535, acknowledgement=65535, windowMode=0):
        self.show("Dropping one matching packet at node %d" % relay)
        self.sim.cmdTestDrop(relay, source, destination, srcPort, destPort,
                             flags, sequence, acknowledgement, windowMode)
        self.sim.runTime(2)

    def pause(self):
        self.show("Pausing the server's test reader")
        self.sim.cmdTestPause(SERVER, CLIENT, SOURCE_PORT, SERVER_PORT)

    def resume(self):
        self.show("Resuming the server's test reader")
        self.sim.cmdTestResume(SERVER, CLIENT, SOURCE_PORT, SERVER_PORT)

    def wait(self, seconds):
        self.show("Running %d simulated seconds" % seconds)
        self.sim.runTime(seconds)

    def outputText(self):
        self.output.flush()
        with open(self.path, "r") as file:
            return file.read()

    def check(self, condition, message):
        if not condition:
            raise AssertionError(message)

    def checkTransfer(self):
        self.show("Checking sent, acknowledged, and received bytes")
        text = self.outputText()
        results = re.findall(
            r"Node (\d+) conn=\d+:\d+->\d+:\d+ accepted=(\d+) acknowledged=(\d+) consumed=(\d+) mismatches=(\d+) result=(\w+)",
            text)
        sent = [x for x in results if x[0] == str(CLIENT) and
                int(x[1]) == TRANSFER_BYTES]
        received = [x for x in results if x[0] == str(SERVER) and
                    int(x[3]) == TRANSFER_BYTES]

        self.check(len(sent) > 0, "Client did not finish the transfer")
        self.check(len(received) > 0, "Server did not finish receiving")
        self.check(any(int(x[2]) == TRANSFER_BYTES and x[5] == "PASS"
                       for x in sent), "Client did not acknowledge all bytes")
        self.check(any(int(x[4]) == 0 and x[5] == "PASS" for x in received),
                   "Server reported missing or incorrect bytes")
        self.check("Sending data" in text, "No DATA transmission was logged")
        self.check("outstanding=12" in text or "outstanding=24" in text,
                   "Multiple outstanding segments were not observed")
        self.show("1025 bytes sent, acknowledged, and received correctly")

    def checkClose(self):
        self.show("Checking successful close on both nodes")
        text = self.outputText()
        closes = re.findall(r"Node (\d+) closed fd=\d+ result=(\d+)", text)
        for node in (SERVER, CLIENT):
            self.check(any(int(n) == node and int(result) == 0
                           for n, result in closes),
                       "Node %d did not close successfully" % node)
        self.check(not any(int(result) != 0 for n, result in closes
                           if int(n) in (SERVER, CLIENT)),
                   "A connection close failed")

    def checkDrop(self):
        self.check("dropped transport packet" in self.outputText(),
                   "The selected packet was not dropped")
        self.show("Confirmed the packet was dropped")

    def checkDataRetry(self):
        self.check("Resending data" in self.outputText(),
                   "Sender did not retransmit DATA")
        self.show("Confirmed DATA retransmission")

    def checkControlRetry(self):
        self.check("retransmitted TCP control" in self.outputText(),
                   "Missing handshake retransmission")
        self.show("Confirmed handshake retransmission")

    def checkZeroWindow(self):
        self.check("wnd=0" in self.outputText(),
                   "Receiver never advertised a zero window")
        self.show("Receiver advertised a zero window")

    def checkFailure(self):
        text = self.outputText().lower()
        self.check("connection failed" in text or "handshake timeout" in text,
                   "Missing failed connection message")
        self.check("released failed socket" in text,
                   "Failed connection did not release its socket")
        self.check("test passed" not in text,
                   "Failed connection was reported as successful")
        self.show("Connection failure and socket cleanup confirmed")

    def finish(self):
        self.output.close()
        self.show("PASS")
        print("Log saved to " + self.path)


def basicTransfer(test, seconds=360):
    test.startServer()
    test.startClient()
    test.wait(seconds)
    test.checkTransfer()
    test.checkClose()
    test.finish()
