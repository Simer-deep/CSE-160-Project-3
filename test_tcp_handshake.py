from TestSim import TestSim

sim = TestSim(seed=1)

# Enable logs.
sim.addChannel("transport")
# sim.addChannel("routing")
# sim.addChannel("command")

# Load our four-node network.
sim.loadTopo("tcp-line.topo")

# Use the professor's noise model.
sim.loadNoise("no_noise.txt")

# Start all four nodes.
sim.bootAll()

print("Waiting for routing tables to converge...")
sim.runTime(60)

# Start the TCP server on Node 1.
print("Starting TCP server on Node 1...")
sim.testServer(1)
sim.runTime(2)

# Start the TCP client on Node 4.
print("Starting TCP client on Node 4...")
sim.testClient(4)

# Run the simulation long enough for the handshake.
sim.runTime(20)

print("TCP handshake test finished.")