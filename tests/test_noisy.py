from tcp_common import TransportCase, basicTransfer

def run():
    test = TransportCase("noisy", "some_noise.txt")
    test.show("Checking a complete transfer with network noise")
    basicTransfer(test, 500)
