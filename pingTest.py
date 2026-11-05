import os
import subprocess
import sys


def main():
    directory = os.path.dirname(os.path.abspath(__file__))
    tests = ("line", "alternate", "partition", "poison", "capacity", "loss_ttl")
    for name in tests:
        script = "test_dv_%s.py" % name
        print("Running " + script)
        sys.stdout.flush()
        subprocess.check_call([sys.executable, os.path.join(directory, script)], cwd=directory)


if __name__ == "__main__":
    main()
