from __future__ import print_function

import os
import subprocess
import sys

TESTS = ["baseline", "data_loss", "ack_loss", "flow",
         "syn_loss", "handshake_ack_loss", "close_ack_loss",
         "failure", "noisy"]

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in TESTS + ["all"]:
        print("Usage: python run.py <test name|all>")
        print("Tests: " + ", ".join(TESTS))
        return 2

    name = sys.argv[1]
    if name == "all":
        failed = []
        for test in TESTS:
            print("\nRunning " + test)
            sys.stdout.flush()
            result = subprocess.call(
                [sys.executable, os.path.abspath(__file__), test],
                cwd=os.path.dirname(os.path.abspath(__file__))
            )
            if result != 0:
                failed.append(test)

        if failed:
            print("\nFailed: " + ", ".join(failed))
            return 1

        print("\nAll nine tests passed")
        return 0

    folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests")
    sys.path.insert(0, folder)

    try:
        test = __import__("test_" + name)
        test.run()
    except Exception as error:
        print("[%s] FAIL: %s" % (name, error))
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
