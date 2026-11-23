from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, SYN

def run():
    test = TransportCase("syn_loss")
    test.show("Checking recovery after a missing SYN")
    test.startServer()
    test.drop(3, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, SYN,
              sequence=410)
    test.startClient()
    test.wait(360)
    test.checkDrop()
    test.checkControlRetry()
    test.checkTransfer()
    test.checkClose()
    test.finish()
