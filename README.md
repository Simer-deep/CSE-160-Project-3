# Project 2: Distance Vector Routing

This project uses distance vector routing to find minimum-hop paths between nodes. Each node learns routes from its neighbors and uses the next hop to send ping packets and replies. Neighbor discovery and Project 1 flooding stay separate from routed traffic.

## Build and run

Use the course TinyOS environment with nesC, the micaz simulator tools, and the TinyOS Python libraries. The supplied TOSSIM files use Python 2.7, so `python` below should point to that interpreter. `TINYOS_ROOT_DIR` and `PYTHONPATH` should be set by the course environment.

Run these commands from the project folder:

```sh
make micaz sim
python pingTest.py
```

Build again after changing any `.nc` or `.h` files. `pingTest.py` runs all six tests in separate processes so each starts with a fresh simulator. It stops if a test fails.

To run a single test:

```sh
python test_dv_line.py
python test_dv_alternate.py
python test_dv_partition.py
python test_dv_poison.py
python test_dv_capacity.py
python test_dv_loss_ttl.py
```

## Tests and results

The build and all six tests passed. The table lists what each test checks.

All links below have both radio directions at a gain of -54 dBm unless the test changes them. The first five tests use `noise/no_noise.txt`. The loss and TTL test uses `noise/dv_lossy.txt`. Link failure tests keep all nodes running.

| Test | Topology file and links | Expected result | Result |
| --- | --- | --- | --- |
| Line | `topo/dv_line.topo`: 1-2, 2-3, 3-4 | Routes 1 to 4 and 4 to 1 have cost 3, with next hops 2 and 3. Ping and reply use routing without flooding. | Passed |
| Alternate route | `topo/dv_alternate.topo`: 1-2, 2-4, 1-3, 3-5, 5-4 | Node 1 uses 2 to reach 4 at cost 2. Remove both 2-4 directions: it uses 1-3-5-4 at cost 3. Restore the link: it returns to cost 2. | Passed |
| Partition | `topo/dv_line.topo`: 1-2, 2-3, 3-4 | Remove both 2-3 directions: node 1 withdraws its route to 4 and drops a ping without flooding. Restore the link: routes and replies recover. | Passed |
| Poison reverse | `topo/dv_poison.topo`: 1-2, 2-3, 3-4 | Node 2 reaches 4 through 3 at cost 2. Node 3 receives cost 16 for destination 4 from node 2, while node 1 receives cost 2. Self stays at cost 0. | Passed |
| Packet capacity | `topo/dv_capacity.topo`: node 1 connects to nodes 2 through 12 | Twelve routes need multiple packets. Node 2 learns a later-packet route, pings it through node 1, and keeps it after an unrelated partial update. | Passed |
| Loss and TTL | `topo/dv_line.topo`: 1-2, 2-3, 3-4 | Weakening link 2-3 causes missed DV updates. Restoring it recovers updates and ping. A ping with TTL 1 at relay 2 expires without delivery or a reply. | Passed |

Each test writes its output to `logs/<test_name>.log`, such as `logs/test_dv_line.log`. The logs include the input files, directed links, boot order, commands, simulated times, expected results, and PASS or FAIL checks. Running a test again replaces that test's log. A failed check raises an error and gives a nonzero exit status.

## Test setup and waiting times

Tests use random seed 1 and boot nodes in ascending ID order at tick `1333 * nodeID`. The command, general, neighbor, flooding, and routing channels are enabled. `TestSim.runTime()` measures simulated seconds using the simulator clock and `ticksPerSecond()`. Logs show the actual phase times.

Startup waits are 60 seconds, or 90 for the larger capacity test. This gives discovery and several DV rounds time to run. Failure and recovery waits are 120 seconds to cover neighbor removal, which can take about 18 seconds, and many 5 to 6 second DV rounds. These are wait budgets for the supplied topologies; checks still have to pass.

Poison reverse and capacity each collect 12 more seconds of updates. The partition test samples the table about every 5 seconds to catch withdrawal before removal. Capacity briefly pauses link 1-2 during the partial-update check so a full update cannot hide a dropped route.

Pings get 10 seconds for a reply, or 20 in the loss test. The TTL drop is watched for 10 seconds. Route-table commands get 1 second.

## Noise and packet loss

`noise/no_noise.txt` has 155 readings at -98 dBm for a quiet background. `noise/dv_lossy.txt` repeats a 16-reading pattern ten times: eight at -98 dBm, four at -85 dBm, two at -75 dBm, and two at -65 dBm.

The loss test also weakens both directions of 2-3 to -120 dBm for 9 seconds. The first second clears earlier packets; the next 8 seconds must show queued DV traffic from node 2 but no matching reception at node 3. After restoring -54 dBm, both nodes must receive updates again. The noise file stays the same throughout.

The separate TTL check injects a ping with source 1, destination 4, sequence 60000, and TTL 1 at node 2. Node 2 must log the drop without forwarding it.

## Settings and limits

| Setting | Value |
| --- | --- |
| Infinity | 16; usable route costs are 0 through 15 |
| Routing table | 32 entries, including self and retained withdrawals |
| Neighbor table | 15 entries |
| SimpleSend pool and queue | 20 packets each per sender instance |
| Command handler pool and queue | 20 messages each |
| Flooding duplicate cache | 15 source and sequence pairs |
| Packet size | 28 bytes: 8 bytes of header and 20 bytes of payload |
| DV packet capacity | 9 destination-cost pairs after the count byte |
| Starting packet TTL | 32 for routed pings and replies |
| First neighbor probe | After 3 to 4 seconds |
| Later neighbor probes | Every 5 to 6 seconds; removal after 3 missed rounds |
| DV updates | Start after 5 to 6 seconds, then repeat every 5 to 6 seconds |
| DV packet spacing | 150 ms; retry after 250 ms if the send queue is full |
| Route maintenance | Every 1 second |
| Learned route timeout | 20 seconds without a fresh entry from the selected next hop |
| Withdrawal retention | 30 seconds before removing the entry |

Node IDs are at most 255. The DV payload uses one count byte followed by one-byte destination and one-byte cost pairs. Longer vectors use more packets. The packet header keeps 16-bit destination, source, and sequence fields in network byte order, plus one-byte TTL and protocol fields.

Radio AM types are 7 for neighbor discovery, 8 for DV, 9 for routed IP, and 6 for retained flooding. The network protocol values are 0 for PING, 1 for PINGREPLY, and 5 for DV.

## Routing behavior

Each node keeps one selected route per destination. Self costs 0, a confirmed neighbor costs 1, and learned routes add 1 to the advertised cost, capped at 16. Equal costs keep the valid current next hop. Updates from that next hop can increase the cost or make the route unreachable. Alternatives can be learned from later updates.

Freshness is tracked per learned route. A route expires after 20 seconds without its own refresh, even if its next hop is still a neighbor. Losing that neighbor also invalidates the route. Withdrawals stay for 30 seconds before removal. Repeated infinity updates do not restart that timer, and a finite update restores the route. These timers allow several normal DV rounds for refresh and withdrawal.

DV sends one-hop unicast updates to each neighbor. A route is advertised as infinity to its selected next hop and at its normal cost to other neighbors. Self is always 0. This is poison reverse. Missing an entry from one packet does not withdraw it. Poison reverse handles two-node loops; TTL bounds how long a packet can circulate in a longer loop.

IP preserves source, destination, sequence, protocol, and payload. Relays drop TTL values of 0 or 1 and otherwise subtract 1. Local delivery needs a positive TTL. Replies use routing too. Missing routes are logged and dropped without flooding. Routed IP does not use the flooding duplicate cache.

`SimpleSend` copies packets into its fixed queue and keeps the radio buffer until `sendDone`. Queued does not mean delivered. Immediate radio rejection is retried later. A full route table ignores new destinations until space frees. DV retries a full send queue after 250 ms; IP logs and drops a rejected submission.

## Commands and output

The tests use the existing command handler through these helpers:

| Call | Action |
| --- | --- |
| `s.ping(1, 4, "hello")` | Ask node 1 to send a routed ping to node 4 |
| `s.routeDMP(1)` | Print node 1's routing table |
| `s.neighborDMP(1)` | Print node 1's neighbors |
| `s.removeLink(2, 3)` | Remove both radio directions of link 2-3 |
| `s.restoreLink(2, 3)` | Restore both directions using the original topology gains |

Routing-table output uses `Dest NextHop Cost State`. A reachable entry can look like `4 2 3 VALID`. A withdrawn entry looks like `4 NONE INF WITHDRAWN` and cannot be used for forwarding.

Routing and forwarding messages use the routing debug channel. For example, an accepted ping submission can look like this:

```text
Node 1 Routing Packet - src: 1, dest: 4, seq: 0, next hop: 2, cost: 3, TTL: 32
```
