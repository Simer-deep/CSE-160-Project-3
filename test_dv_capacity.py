import re

from dv_test import DVTest


def main():
    test = DVTest("test_dv_capacity", "dv_capacity.topo")
    test.wait(90, "let all 12 routes settle; each DV packet holds only nine entries")
    test.check(len(test.table(1)) == 12, "node 1 learned all 12 routes")
    start = test.mark()
    test.wait(12, "watch a full DV update round")
    offset = 0
    later = []
    text = test.read(start)
    for line in text.splitlines():
        chunk = re.search(r"Node 1 queued (\d+) routes for neighbor 2 starting at (\d+)", line)
        if chunk:
            offset = int(chunk.group(2))
        entry = re.search(r"Node 1 to neighbor 2: Dest (\d+) Advertised Cost (\d+)", line)
        if entry:
            destination, cost = map(int, entry.groups())
            if offset >= 9 and destination != 2 and cost < 16:
                later.append(destination)
    test.check(bool(later), "node 1 put routes in a second packet")
    destination = later[0]
    test.check("Node 2 received from neighbor 1: Dest %d Advertised Cost 1" % destination in text,
               "node 2 received a route from the second packet")
    test.route(2, destination, 1, 2)
    test.ping(2, destination, [2, 1, destination])
    test.phase("pause link 1-2 so regular updates cannot hide a dropped route")
    test.s.removeLink(1, 2)
    test.s.runTime(1)
    test.phase("send node 2 an update with only node 1's self-route")
    start = test.mark()
    test.s.injectDV(1, 2, [(1, 0)])
    test.s.runTime(0.01)
    test.check("Node 2 received from neighbor 1: Dest 1 Advertised Cost 0" in test.read(start),
               "node 2 received the partial update")
    test.route(2, destination, 1, 2)
    test.s.restoreLink(1, 2)
    test.finish()


if __name__ == "__main__":
    main()
