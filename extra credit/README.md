# Congestion Control Extra Credit

This is the optional slow start and AIMD version of Project 3. Run these commands inside Docker from `/root/project`.

## 1. Fixed-window test

```bash
make clean && make micaz sim
python2 "extra credit/tests/compare.py" fixed
```

## 2. Congestion-control test

```bash
make clean && make EXTRA_CREDIT=1 micaz sim
python2 "extra credit/tests/compare.py" congestion
```

## 3. Generate results

```bash
python2 "extra credit/tests/report.py"
```

Run both tests before generating the report.

## Files

- `interfaces/CongestionControl.nc` - congestion-control interface
- `modules/CongestionControlP.nc` - slow start and AIMD
- `tests/compare.py` - two 1,025-byte flows sharing node 2
- `tests/report.py` - throughput, retransmissions, fairness, and window graph

## How it works

The sender starts with a 12-byte congestion window. New ACKs increase the window, first quickly and then gradually. On a DATA timeout, the threshold is halved and the congestion window resets to 12 bytes. New transmissions are limited by the congestion window, receiver window, and available send buffer.

Both tests use the same topology, traffic, random seed, and packet drop. A timeout is the congestion signal, but wireless loss can also cause timeouts.

Results are saved in `extra credit/results/`:

- `comparison.md` - readable comparison
- `comparison.csv` - per-flow numbers
- `cwnd.svg` - congestion-window graph
- `fixed.log` and `congestion.log` - raw logs

Keep the results when submitting; the generated results folder is not tracked by Git.
