from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, DATA

def run():
    test = TransportCase("data_loss")
    test.show("Checking that a lost DATA packet gets resent")
    test.startServer()
    test.drop(3, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, DATA,
              sequence=411)
    test.startClient()
    test.wait(360)
    test.checkDrop()
    test.checkDataRetry()
    test.checkTransfer()
    test.checkClose()
    test.finish()
