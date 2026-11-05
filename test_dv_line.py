from dv_test import DVTest

def main():
    test = DVTest("test_dv_line", "dv_line.topo")
    test.wait(60, "allow neighbor discovery and several DV rounds")
    test.route(1, 4, 2, 3)
    test.route(4, 1, 3, 3)
    test.ping(1, 4, [1, 2, 3, 4])
    test.finish()

if __name__ == "__main__":
    main()
