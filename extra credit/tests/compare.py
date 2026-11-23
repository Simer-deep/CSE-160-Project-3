from __future__ import print_function

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RESULTS = os.path.join(os.path.dirname(HERE), "results")
sys.path.insert(0, ROOT)

from TestSim import TestSim

BYTES = 1025
FLOWS = [(3, 11), (4, 10)]


def snapshot(path):
    with open(path, "r") as source:
        return source.read()


def finished(text, node, port):
    pattern = (r"Node %d conn=%d:%d->1:20 accepted=%d "
               r"acknowledged=%d consumed=0 mismatches=0 result=PASS" %
               (node, node, port, BYTES, BYTES))
    return re.search(pattern, text) is not None


def delivered(text, node, port):
    pattern = (r"Node 1 conn=1:20->%d:%d accepted=0 "
               r"acknowledged=0 consumed=%d mismatches=0 result=PASS" %
               (node, port, BYTES))
    return re.search(pattern, text) is not None


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("fixed", "congestion"):
        print("Usage: python2 compare.py fixed|congestion")
        return 2

    mode = sys.argv[1]
    if not os.path.isdir(RESULTS):
        os.makedirs(RESULTS)

    path = os.path.join(RESULTS, mode + ".log")
    output = open(path, "w")
    sim = TestSim(seed=1)
    for channel in ("Project3TGen", "transport", "routing", "command"):
        sim.addChannel(channel, output)

    print("[%s] Loading the shared 1-2-3-4 line topology" % mode)
    sim.loadTopo("tcp-line.topo")
    sim.loadNoise("no_noise.txt")
    sim.bootAll()
    sim.runTime(65)
    sim.ping(4, 1, "route")
    sim.ping(3, 1, "route")
    sim.runTime(3)
    sim.cmdTestServer(1, 20)
    sim.runTime(2)

    print("[%s] Dropping one DATA packet on the shared relay node 2" % mode)
    sim.cmdTestDrop(2, 4, 1, 10, 20, 8, sequence=411)
    sim.runTime(2)

    print("[%s] Starting two competing 1025-byte clients: nodes 3 and 4" % mode)
    for node, port in FLOWS:
        sim.cmdTestClient(node, 1, port, 20, BYTES)

    start = sim.seconds()
    completion = {}
    for unused in range(120):
        sim.runTime(5)
        output.flush()
        logs = snapshot(path)
        for node, port in FLOWS:
            if str(node) not in completion and finished(logs, node, port):
                completion[str(node)] = round(sim.seconds() - start, 2)
        if len(completion) == 2 and all(
                delivered(logs, node, port) for node, port in FLOWS):
            if len(re.findall(r"Node 1 closed fd=\d+ result=0", logs)) >= 2:
                if all(re.search(r"Node %d closed fd=\d+ result=0" % node,
                                 logs) for node, unused_port in FLOWS):
                    break

    output.flush()
    logs = snapshot(path)
    output.close()
    results = {
        "mode": mode,
        "topology": "tcp-line.topo",
        "noise": "no_noise.txt",
        "random_seed": 1,
        "bytes_per_flow": BYTES,
        "duration_seconds": round(sim.seconds() - start, 2),
        "dropped_packets": len(re.findall(r"dropped transport packet", logs)),
        "flows": []
    }

    all_pass = True
    for node, port in FLOWS:
        sent = finished(logs, node, port)
        received = delivered(logs, node, port)
        closed = (re.search(r"Node %d closed fd=\d+ result=0" % node,
                            logs) is not None)
        elapsed = completion.get(str(node))
        passed = sent and received and closed and elapsed is not None
        all_pass = all_pass and passed
        retries = len(re.findall(
            r"Node %d conn=[^\n]* Resending data" % node, logs))
        results["flows"].append({
            "node": node,
            "port": port,
            "passed": passed,
            "bytes": BYTES if passed else 0,
            "completion_seconds": elapsed,
            "throughput_bytes_per_second": (
                round(float(BYTES) / elapsed, 2) if elapsed else 0),
            "data_retransmissions": retries
        })

    results["passed"] = all_pass
    results_file = os.path.join(RESULTS, mode + ".json")
    with open(results_file, "w") as result_file:
        json.dump(results, result_file, indent=2, sort_keys=True)

    for flow in results["flows"]:
        print("[%s] Node %d: %s, %.2f B/s, %d retransmissions" %
              (mode, flow["node"], "PASS" if flow["passed"] else "FAIL",
               flow["throughput_bytes_per_second"],
               flow["data_retransmissions"]))

    print("[%s] Log: %s" % (mode, path))
    return 0 if all_pass and results["dropped_packets"] > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
