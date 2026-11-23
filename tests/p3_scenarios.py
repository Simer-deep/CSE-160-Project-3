from __future__ import print_function

import os
import re
import sys

from TestSim import TestSim

SERVER = 1
CLIENT = 4
PORT = 20
SOURCE_PORT = 10
LENGTH = 1025
FLAGS_SYN = 1
FLAGS_ACK = 2
FLAGS_SYN_ACK = 3
FLAGS_DATA = 8

class TimeLogger:
    def __init__(self, sim, output):
        self.sim = sim
        self.output = output
        self.startOfLine = True

    def write(self, message):
        for part in message.splitlines(True):
            if self.startOfLine:
                self.output.write("t=%.3f " % self.sim.seconds())
            self.output.write(part)
            self.startOfLine = part.endswith("\n")

    def flush(self):
        self.output.flush()

def check(condition, message):
    if not condition:
        raise AssertionError(message)

def log_text(path):
    with open(path, "r") as file:
        return file.read()

def check_transfer(text, expected, clients=1):
    results = re.findall(
        r"accepted=(\d+) acknowledged=(\d+) consumed=(\d+) mismatches=(\d+) result=(\w+)",
        text)
    producers = [x for x in results if int(x[0]) == expected]
    consumers = [x for x in results if int(x[2]) == expected]
    check(len(producers) >= clients, "Missing producer result for %d bytes" % expected)
    check(len(consumers) >= clients, "Missing receiver result for %d bytes" % expected)
    for item in producers:
        check(int(item[1]) == expected and item[4] == "PASS",
              "Sender did not acknowledge all expected bytes")
    for item in consumers:
        check(int(item[3]) == 0 and item[4] == "PASS",
              "Receiver reported incorrect bytes")
    check("Resending data" not in text or "Received ACK" in text,
          "Retransmission log without any acknowledgment")

def run_scenario(name, noise="no_noise.txt", seconds=360):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    logs = os.path.join(root, "logs")
    if not os.path.isdir(logs):
        os.makedirs(logs)
    path = os.path.join(logs, "tcp_%s.log" % name)

    sim = TestSim(seed=1)
    output = open(path, "w")
    log = TimeLogger(sim, output)
    sim.addChannel("Project3TGen", log)
    sim.addChannel("transport", log)
    sim.addChannel("routing", log)
    sim.loadTopo("tcp-line.topo")
    sim.loadNoise(noise)
    sim.bootAll()
    sim.runTime(65)
    sim.ping(CLIENT, SERVER, "route")
    sim.runTime(3)

    if name != "failure":
        sim.cmdTestServer(SERVER, PORT)
        sim.runTime(2)

    if name == "data_loss":
        sim.cmdTestDrop(3, CLIENT, SERVER, SOURCE_PORT, PORT,
                        FLAGS_DATA, sequence=411)
    elif name == "ack_loss":
        sim.cmdTestDrop(2, SERVER, CLIENT, PORT, SOURCE_PORT,
                        FLAGS_ACK, acknowledgement=423)
    elif name == "syn_loss":
        sim.cmdTestDrop(3, CLIENT, SERVER, SOURCE_PORT, PORT,
                        FLAGS_SYN, sequence=410)
    elif name == "synack_loss":
        sim.cmdTestDrop(2, SERVER, CLIENT, PORT, SOURCE_PORT,
                        FLAGS_SYN_ACK)
    elif name == "handshake_ack_loss":
        sim.cmdTestDrop(3, CLIENT, SERVER, SOURCE_PORT, PORT,
                        FLAGS_ACK, acknowledgement=121)
    elif name == "close_ack_loss":
        sim.cmdTestDrop(3, CLIENT, SERVER, SOURCE_PORT, PORT,
                        FLAGS_ACK, acknowledgement=122)

    if name in ("data_loss", "ack_loss", "syn_loss",
                "synack_loss", "handshake_ack_loss", "close_ack_loss"):
        sim.runTime(2)

    if name == "two_connections":
        sim.cmdTestClient(3, SERVER, SOURCE_PORT, PORT, LENGTH)
        sim.cmdTestClient(CLIENT, SERVER, SOURCE_PORT, PORT, LENGTH)
        sim.runTime(seconds)
    elif name == "flow":
        sim.cmdTestClient(CLIENT, SERVER, SOURCE_PORT, PORT, LENGTH)
        sim.cmdTestPause(SERVER, CLIENT, SOURCE_PORT, PORT)
        sim.runTime(90)
        output.flush()
        check("wnd=0" in log_text(path),
              "Receiver did not advertise a zero window")
        sim.cmdTestDrop(2, SERVER, CLIENT, PORT, SOURCE_PORT,
                        FLAGS_ACK, windowMode=2)
        sim.runTime(2)
        sim.cmdTestResume(SERVER, CLIENT, SOURCE_PORT, PORT)
        sim.runTime(seconds)
    else:
        sim.cmdTestClient(CLIENT, SERVER, SOURCE_PORT, PORT, LENGTH)
        sim.runTime(seconds)

    output.flush()
    output.close()
    text = log_text(path)

    if name == "failure":
        check("connection failed" in text.lower() or
              "handshake timeout" in text.lower(),
              "Unavailable listener did not cause a reported failure")
        check("test passed" not in text.lower(),
              "Unavailable listener was reported as success")
        check("released failed socket" in text,
              "Failed connection did not release its socket")
    else:
        check_transfer(text, LENGTH, 2 if name == "two_connections" else 1)
        check("closed fd=" in text, "Missing completed orderly close")
        check("Sending data" in text, "Missing data transmission log")
        check("outstanding=12" in text or "outstanding=24" in text,
              "Multiple outstanding segments not shown")
        if name in ("data_loss", "ack_loss", "syn_loss",
                    "synack_loss", "handshake_ack_loss", "close_ack_loss", "flow"):
            check("dropped transport packet" in text,
                  "The selected packet was never dropped")
        if name == "data_loss":
            check("Resending data" in text,
                  "No DATA retransmission was logged")
        if name == "data_loss":
            check("Wrong sequence number" in text and "ack=411" in text,
                  "Missing cumulative ACK at the lost data gap")
        if name in ("syn_loss", "synack_loss", "handshake_ack_loss"):
            check("retransmitted TCP control" in text,
                  "Missing control packet retransmission")
        if name == "flow":
            check("resumed the receiver" in text,
                  "Receiver was not resumed")

    print("%s: PASS (log: %s)" % (name, path))

def main():
    required = ["baseline", "data_loss", "ack_loss", "flow",
                "syn_loss", "handshake_ack_loss", "close_ack_loss",
                "failure", "noisy"]
    optional = ["synack_loss", "heavy_noise", "two_connections"]
    names = required + optional
    if len(sys.argv) < 2 or sys.argv[1] not in names + ["all"]:
        print("Usage: python run.py <scenario|all>")
        print("Scenarios: %s" % ", ".join(names))
        return 2

    requested = required if sys.argv[1] == "all" else [sys.argv[1]]
    failed = []

    for name in requested:
        try:
            if name == "noisy":
                run_scenario(name, noise="some_noise.txt", seconds=500)
            elif name == "heavy_noise":
                run_scenario(name, noise="meyer-heavy.txt", seconds=700)
            else:
                run_scenario(name)
        except Exception as error:
            print("%s: FAIL (%s)" % (name, error))
            failed.append(name)

    if failed:
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
