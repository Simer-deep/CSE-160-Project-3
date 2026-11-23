import os
import subprocess
import sys

def main():
    folder = os.path.dirname(os.path.abspath(__file__))
    return subprocess.call(
        [sys.executable, os.path.join(folder, "run.py"), "all"],
        cwd=folder
    )

if __name__ == "__main__":
    sys.exit(main())
