from TestSim import TestSim

def main():
    sim = TestSim(seed=1)
    sim.runTime(1)
    sim.loadTopo("pizza.topo")
    sim.loadNoise("meyer-heavy.txt")
    sim.bootAll()
    sim.addChannel(sim.COMMAND_CHANNEL)
    sim.addChannel(sim.GENERAL_CHANNEL)
    sim.addChannel(sim.TRANSPORT_CHANNEL)
    sim.addChannel(sim.TEST_CHANNEL)
    sim.runTime(300)
    sim.testServer(1)
    sim.runTime(60)
    sim.testClient(13)
    sim.runTime(1000)

if __name__ == "__main__":
    main()
