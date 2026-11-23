# Congestion Control Extra Credit

This is separate from the required Project 3 tests. The normal build still uses the fixed 48-byte window.

## Run

In the TinyOS Docker container, from the project folder:

```sh
sh "extra credit/run.sh"
```

This builds both versions, runs the same two-flow test, saves the results, and rebuilds the regular version at the end.

## Files

- `interfaces/CongestionControl.nc` - commands used by the stream
- `modules/CongestionControlP.nc` - slow start and AIMD
- `tests/compare.py` - sends two 1,025-byte flows through node 2
- `tests/report.py` - makes the comparison table and graph
- `run.sh` - runs everything

The extra-credit build uses `make EXTRA_CREDIT=1 micaz sim`. The regular build uses `make micaz sim`.

## How it works

1. Start `cwnd` at 12 bytes, or one DATA packet.
2. Increase it when new bytes are acknowledged. At first it grows quickly (slow start), then more slowly (additive increase).
3. When a DATA timeout happens, cut `ssthresh` in half and reset `cwnd` to 12 bytes.
4. Before sending new data, use the smallest of `cwnd`, the receiver window, and the normal send limit. Previously sent data can still be retransmitted.
5. Compare the two modes using the same topology, traffic, and packet drop.

The timeout is our congestion signal. A wireless packet loss can also cause a timeout, so the congestion version is not guaranteed to be faster.

## Results

After running, look in `extra credit/results/`:

- `comparison.md` - throughput, retransmissions, and fairness
- `comparison.csv` - results for each client
- `cwnd.svg` - congestion window changes
- `fixed.log` and `congestion.log` - simulator output

Both clients must transfer all 1,025 bytes. The experiment also checks that the congestion window increases and reacts to a timeout.
