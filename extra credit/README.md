# Congestion Control Extra Credit

This adds slow start and AIMD without changing the regular Project 3 build.

## Run

From `/root/project` inside Docker, first run the fixed-window test:

```bash
make clean && make micaz sim
python2 "extra credit/tests/compare.py" fixed
```

Then run congestion control and generate the comparison:

```bash
make clean && make EXTRA_CREDIT=1 micaz sim
python2 "extra credit/tests/compare.py" congestion
python2 "extra credit/tests/report.py"
```

## Files

- `modules/CongestionControlP.nc` - slow start and AIMD
- `interfaces/CongestionControl.nc` - module interface
- `tests/compare.py` - two clients sharing a network link
- `tests/report.py` - results and graph

## How it works

The congestion window starts at 12 bytes. ACKs increase it, first quickly and then gradually. After a DATA timeout, the threshold is halved and the window resets to 12 bytes. New data is limited by the congestion window, receiver window, and send buffer.

The two modes use the same network and packet drop. Results are saved in `extra credit/results/` as `comparison.md`, `comparison.csv`, and `cwnd.svg`.
