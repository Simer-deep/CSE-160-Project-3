from dv_test import DVTest


def main():
    test = DVTest("test_dv_partition", "dv_line.topo")
    test.wait(60, "let the line routes settle")
    test.route(1, 4, 2, 3)
    test.ping(1, 4, [1, 2, 3, 4])
    test.phase("remove radio links 2 -> 3 and 3 -> 2; all nodes stay on")
    test.s.removeLink(2, 3)
    deadline = test.s.seconds() + 120
    withdrawn = False
    while test.s.seconds() < deadline:
        entry = test.table(1).get(4)
        withdrawn = withdrawn or entry == (None, 16, "WITHDRAWN")
        test.s.runTime(4)
    test.check(withdrawn, "node 1 showed destination 4 as NONE INF WITHDRAWN")
    test.unreachable(1, 4)
    test.unreachable(4, 1)
    test.dropped_ping(1, 4)
    test.phase("restore radio links 2 -> 3 and 3 -> 2 at -54 dBm")
    test.s.restoreLink(2, 3)
    test.wait(120, "let the routes recover after restoring the link")
    test.route(1, 4, 2, 3)
    test.route(4, 1, 3, 3)
    test.ping(1, 4, [1, 2, 3, 4])
    test.finish()


if __name__ == "__main__":
    main()
