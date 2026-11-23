from tcp_common import TransportCase

def run():
    test = TransportCase("failure")
    test.show("Checking connection timeout with no server listening")
    test.startClient()
    test.wait(360)
    test.checkFailure()
    test.finish()
