from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK

def run():
    test = TransportCase("ack_loss")
    test.show("Checking that a lost ACK does not duplicate data")
    test.startServer()
    test.drop(2, SERVER, CLIENT, SERVER_PORT, SOURCE_PORT, ACK,
              acknowledgement=423)
    test.startClient()
    test.wait(360)
    test.checkDrop()
    test.checkTransfer()
    test.checkClose()
    test.finish()
