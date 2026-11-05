import re

from dv_test import DVTest


def main():
    test = DVTest("test_dv_loss_ttl", "dv_line.topo", "dv_lossy.txt")
    test.wait(60, "let routes settle with noise samples -98/-85/-75/-65 dBm")
    test.route(1, 4, 2, 3)
    test.phase("weaken both directions of link 2-3 to -120 dBm to force packet loss")
    test.s.setGain(2, 3, -120)
    test.s.runTime(1)
    start = test.mark()
    test.wait(8, "keep nodes running while some DV updates are lost")
    text = test.read(start)
    test.check(re.search(r"Node 2 queued \d+ routes for neighbor 3 starting at", text) is not None,
               "node 2 queued DV packets for node 3")
    test.check("Node 3 received a DV packet from Node 2" not in text,
               "node 3 missed updates from node 2")
    test.phase("restore both directions of link 2-3 to -54 dBm; keep the same noise")
    start = test.mark()
    test.s.setGain(2, 3, -54)
    test.wait(120, "let DV packets get through again and routes settle")
    text = test.read(start)
    test.check("Node 3 received a DV packet from Node 2" in text and
               "Node 2 received a DV packet from Node 3" in text,
               "nodes 2 and 3 received DV updates again")
    test.route(1, 4, 2, 3)
    test.route(4, 1, 3, 3)
    test.ping(1, 4, [1, 2, 3, 4], seconds=20)
    test.phase("inject routed ping src=1 dest=4 seq=60000 TTL=1 at relay 2; expect expiration")
    start = test.mark()
    test.s.injectIP(1, 4, 2, 1, 60000)
    test.wait(10, "check that the ping expires without reaching node 4 or getting a reply")
    text = test.read(start)
    test.check("Node 2 dropped packet because TTL expired - src: 1, dest: 4, seq: 60000, TTL: 1" in text,
               "node 2 dropped the ping at TTL 1")
    test.check("Routing Packet - src: 1, dest: 4, seq: 60000," not in text,
               "the expired ping was not forwarded")
    test.check("Node 4 received PING from Node 1, seq: 60000" not in text and
               "Node 1 received PING REPLY from Node 4, seq: 60000" not in text,
               "the expired ping did not reach node 4 or produce a reply")
    test.finish()


if __name__ == "__main__":
    main()
