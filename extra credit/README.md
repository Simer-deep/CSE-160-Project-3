# Optional extra credit: congestion control

This folder contains the optional congestion-control implementation, experiment, and results generator. The nine required tests and fixed-window protocol are unchanged by default.

## How to run

From the repository root in the course TinyOS Docker container:

```sh
sh "extra credit/run.sh"
```

The script builds **fixed-window mode**, runs a two-flow bottleneck experiment, builds **congestion mode**, runs the identical experiment, writes comparison files, and restores the normal fixed-window build.

To compile one mode yourself:

```sh
make clean && make micaz sim
make clean && make EXTRA_CREDIT=1 micaz sim
```

## The code in presentation order

1. `interfaces/CongestionControl.nc` declares the four commands.
2. `modules/CongestionControlP.nc` implements slow start, additive increase, and timeout-based multiplicative decrease.
3. `includes/socket.h` adds per-connection `cwnd`, `ssthresh`, and ACK credit **only in extra-credit builds**.
4. `lib/modules/TransportStreamP.nc` calls the module on connection initialization, newly acknowledged bytes, and retransmission timeout. The sender enforces the minimum of `cwnd`, the original 48-byte cap, advertised receiver window, and buffer availability.
5. `tests/compare.py` runs two simultaneous 1,025-byte flows through the same link (nodes 3 and 4 send to node 1 through node 2). Both modes use the same topology, drop, traffic, and random seed.
6. `tests/report.py` writes a CSV summary and congestion-window SVG from observed log events.

## Algorithm

- Start at 12 bytes (one DATA segment).
- Slow start: increase `cwnd` by newly acknowledged bytes while below `ssthresh`.
- Congestion avoidance: accumulate acknowledged bytes and add one segment per window acknowledged.
- On DATA retransmission timeout: halve the threshold (at least one segment), reset `cwnd` to one segment, and retransmit.
- The original send window remains the cap: this is a simple, bounded educational AIMD design rather than full TCP Reno.
- Congestion signal: DATA retransmission timeout. This may also reflect wireless packet loss, so a timeout is an imperfect congestion estimate.

## Reported measurements

- Per-flow completed bytes, approximate completion time and throughput (measured in 5-second simulation steps)
- DATA retransmissions by source node and deliberate packet drops
- Jain fairness index based on measured per-flow throughput
- `cwnd` evolution by ACK/timeout event index in an SVG

The comparison is evidence from a **single deterministic TOSSIM run per mode**, not a statistical claim of improved throughput or fairness. A congestion controller does not always outperform the fixed-window baseline, especially when packet losses are unrelated to congestion.

Generated `results/` files are excluded from Git. Keep them for the extra-credit submission after running the experiment.
