from __future__ import print_function

import tempfile

from TestSim import TestSim

sim = TestSim(seed=1)
log = tempfile.TemporaryFile(mode="w+")
sim.addChannel("transport", log)
sim.addChannel("Project3TGen", log)
sim.loadTopo("tcp-line.topo")
sim.loadNoise("no_noise.txt")
sim.bootAll()

sim.runTime(65)
sim.testServer(1)
sim.runTime(2)
sim.testClient(4)
sim.runTime(25)

log.flush()
log.seek(0)
output = log.read()
log.close()

if "Client TCP ESTABLISHED" not in output:
    raise AssertionError("Client handshake did not complete")
if "Server TCP ESTABLISHED" not in output:
    raise AssertionError("Server handshake did not complete")

print("TCP handshake: PASS")
