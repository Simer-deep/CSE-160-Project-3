from dv_test import DVTest

def main():
    test = DVTest("test_dv_alternate", "dv_alternate.topo")
    test.wait(60, "let the initial routes settle")
    test.route(1, 4, 2, 2)
    test.ping(1, 4, [1, 2, 4])
    test.phase("remove radio links 2 -> 4 and 4 -> 2; both nodes stay on")
    test.s.removeLink(2, 4)
    test.wait(120, "wait for the lost link to time out and the longer route to settle")
    test.route(1, 4, 3, 3)
    test.ping(1, 4, [1, 3, 5, 4])
    test.phase("restore radio links 2 -> 4 and 4 -> 2 at -54 dBm")
    test.s.restoreLink(2, 4)
    test.wait(120, "let the restored link return to the shorter route")
    test.route(1, 4, 2, 2)
    test.ping(1, 4, [1, 2, 4])
    test.finish()

if __name__ == "__main__":
    main()
