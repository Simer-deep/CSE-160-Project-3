# Congestion Control Extra Credit

This is optional. The regular Project 3 build still uses the fixed 48-byte window.

## Run in Docker

Run these commands from `/root/project` in this order.

### 1. Run the normal version

```bash
make clean
make micaz sim
python2 "extra credit/tests/compare.py" fixed
```

### 2. Run the congestion control version

```bash
make clean
make EXTRA_CREDIT=1 micaz sim
python2 "extra credit/tests/compare.py" congestion
```

### 3. Make the comparison

```bash
python2 "extra credit/tests/report.py"
```

### 4. Go back to the normal Project 3 version

```bash
make clean
make micaz sim
python2 PingTest1.py
```

## Files

- `interfaces/CongestionControl.nc`: congestion control commands
- `modules/CongestionControlP.nc`: slow start and AIMD
- `tests/compare.py`: two 1,025-byte transfers sharing a bottleneck
- `tests/report.py`: comparison and congestion window graph

## How it works

1. Start with a 12-byte congestion window (`cwnd`).
2. Increase it when data is acknowledged: fast at first, then gradually.
3. When data times out, cut the threshold in half and reset `cwnd` to 12 bytes.
4. Limit new data using the congestion window, receiver window, and send buffer.
5. Compare both modes using the same network and packet drop.

A timeout is treated as congestion, even though wireless loss can also cause one.

## Results

The tests save files in `extra credit/results/`:

- `comparison.md`: throughput, retransmissions, and fairness
- `comparison.csv`: results for each client
- `cwnd.svg`: congestion window graph
- `fixed.log` and `congestion.log`: simulation logs
