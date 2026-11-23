from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK

def run():
    test = TransportCase("handshake_ack_loss")
    test.show("Checking recovery after the last handshake ACK is lost")
    test.startServer()
    test.drop(3, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK,
              acknowledgement=121)
    test.startClient()
    test.wait(360)
    test.checkDrop()
    test.checkControlRetry()
    test.checkTransfer()
    test.checkClose()
    test.finish()
