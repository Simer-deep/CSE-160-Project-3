#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

echo "== Fixed-window baseline =="
make clean
make micaz sim
python2 "extra credit/tests/compare.py" fixed

echo "== Slow start + AIMD =="
make clean
make EXTRA_CREDIT=1 micaz sim
python2 "extra credit/tests/compare.py" congestion

echo "== Results =="
python2 "extra credit/tests/report.py"

echo "== Restore default build =="
make clean
make micaz sim

echo "Extra credit results: extra credit/results/"
