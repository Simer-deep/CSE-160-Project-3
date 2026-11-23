# Project 3: Reliable Transport

This project adds reliable byte transfer on top of our Project 2 distance-vector routing. Transport packets use the normal routed IP service. The client opens a connection, sends bytes, waits for acknowledgments, and closes when the transfer is done.

## Build and run

Use the course TinyOS environment with TOSSIM and Python 2.7.

```sh
make micaz sim
python PingTest1.py
```

`PingTest1.py` runs the nine Project 3 tests in order. It calls `run.py all`, and each test runs in a fresh TOSSIM process with seed 1. The terminal shows what the test is doing, including which node starts, when a packet is dropped, and what is being checked. It prints PASS or FAIL for each test and exits with an error if any test fails.

Each test has its own file under `tests/`. For example, run `python run.py data_loss` to test lost DATA packets or `python run.py flow` to test flow control. `tests/tcp_common.py` contains the repeated setup and checks used by all nine tests.

The old `python pingTest.py` command still runs the six Project 2 routing tests. It is separate from `PingTest1.py`.

## Tests and results

All nine required Project 3 tests passed.

| Test | What it checks | Result |
| --- | --- | --- |
| `baseline` | 1,025 bytes over four nodes, correct order, more than one outstanding segment, and orderly close | Passed |
| `data_loss` | One lost DATA packet, recovery by retransmission, no duplicate bytes | Passed |
| `ack_loss` | One lost ACK, continued progress without duplicate delivery | Passed |
| `flow` | Pause receiver, fill the 128-byte buffer, lose the reopening update, then resume | Passed |
| `syn_loss` | Lost SYN, handshake retry, no duplicate connection | Passed |
| `handshake_ack_loss` | Lost final handshake ACK and correct recovery | Passed |
| `close_ack_loss` | Lost final closing ACK and connection cleanup | Passed |
| `failure` | Unavailable listener, bounded failure and socket cleanup | Passed |
| `noisy` | Multi-hop transfer using `some_noise.txt` | Passed |

The tests use `topo/tcp-line.topo`, a four-node line from 1 through 4. Most tests use `noise/no_noise.txt`. The noisy test uses `noise/some_noise.txt`. Routing is given 65 simulated seconds to settle before transport starts, and the scripts send a routed ping before the transfer.

Each test saves its detailed output in `logs/tcp_<test_name>.log`. The terminal shows the main steps and the log shows simulated time, packet events, acknowledgments, retries, byte counts, and final results. A successful close is checked on both nodes.

## Transport implementation

`TransportControlP.nc` handles connection setup, closing, and socket records. `TransportStreamP.nc` handles data buffers, sequence numbers, ACKs, windows, and retransmissions. `TransportTestP.nc` generates and checks test data. `Node.nc` connects the application tests to transport.

The test producer generates byte `k % 256` at position `k`. The receiver checks each byte as it reads it. It tracks accepted, acknowledged, and consumed bytes separately, so a successful local send is not confused with delivery to the receiver.

The receiver only accepts data in order. If a segment is duplicated or arrives out of order, it keeps its current cumulative ACK. The sender resends unacknowledged bytes after the timeout. When the receiver's buffer is full, the advertised window becomes zero and the sender stops sending new data.

## Packet and timer settings

| Setting | Value |
| --- | --- |
| TinyOS packet payload budget | 29 bytes |
| Network header | 8 bytes |
| Transport header | 9 bytes |
| Maximum data per segment | 12 bytes |
| Send buffer per connection | 128 bytes |
| Receive buffer per connection | 128 bytes |
| Fixed sender window | 48 bytes |
| Socket table | 3 entries |
| Retransmission timeout | 2 seconds |
| Retry limit | 8 |
| Stall timeout | 60 seconds |
| TIME_WAIT retention | 20 seconds |

The transport header contains source and destination ports, flags, a 16-bit sequence number, a 16-bit acknowledgment, a receive window, and a data length. Multi-byte fields use big-endian order. The network layer adds the end-to-end node addresses, IP packet ID, and TTL.

The stream uses 16-bit sequence numbers without wraparound. Transfers must keep their data and FIN below the documented 65,534 sequence-position limit, including their initial sequence number. The full test transfer is 1,025 bytes, not limited to the 128-byte buffers.

## Test commands

`TestSim.py` provides these helpers:

```python
sim.cmdTestServer(1, 20)
sim.cmdTestClient(4, 1, 10, 20, 1025)
sim.cmdClientClose(4, 1, 10, 20)
sim.cmdTestPause(1, 4, 10, 20)
sim.cmdTestResume(1, 4, 10, 20)
```

The client command supplies the client node, server node, source port, destination port, and number of bytes. The expected byte count is also sent to the server's test consumer, separately from the transport data. Pause and resume only stop the test application from reading; transport reception continues.

Loss tests use `cmdTestDrop()` on a relay to discard one selected transport packet. The hook is off in normal runs, and each deliberate drop is logged. The `Project3TGen` channel shows data and test progress; `transport` shows connection events. Use `routing` when troubleshooting the network layer.

## Optional extra credit

The optional congestion-control code and two-flow comparison are in `extra credit/`. The default build uses the original fixed window. See `extra credit/README.md` for the exact `make micaz sim` and Python test commands, in order.
