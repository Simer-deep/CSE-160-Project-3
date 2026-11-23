from __future__ import print_function

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "tests"))
from p3_scenarios import main

if __name__ == "__main__":
    sys.exit(main())
