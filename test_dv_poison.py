from dv_test import DVTest


def main():
    test = DVTest("test_dv_poison", "dv_poison.topo")
    test.wait(60, "node 2 reaches 4 through 3; node 1 is its other neighbor")
    test.route(2, 4, 3, 2)
    start = test.mark()
    test.wait(12, "watch two DV update rounds")
    text = test.read(start)
    test.check("Node 2 to neighbor 3: Dest 4 Advertised Cost 16" in text,
               "node 2 sends cost 16 for destination 4 to node 3")
    test.check("Node 2 to neighbor 1: Dest 4 Advertised Cost 2" in text,
               "node 2 sends cost 2 for destination 4 to node 1")
    test.check("Node 3 received from neighbor 2: Dest 4 Advertised Cost 16" in text,
               "node 3 received the poisoned route")
    test.check("Node 1 received from neighbor 2: Dest 4 Advertised Cost 2" in text,
               "node 1 received the finite route")
    for neighbor in (1, 3):
        test.check("Node 2 to neighbor %d: Dest 2 Advertised Cost 0" % neighbor in text,
                   "self-route stays cost 0 for neighbor %d" % neighbor)
    test.route(3, 4, 4, 1)
    test.phase("node 3 cannot use node 2 as a route back to 4, preventing a two-node loop")
    test.ping(2, 4, [2, 3, 4])
    test.finish()


if __name__ == "__main__":
    main()
