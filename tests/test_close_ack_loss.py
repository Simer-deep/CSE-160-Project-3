from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK

def run():
    test = TransportCase("close_ack_loss")
    test.show("Checking close when a FIN ACK is lost")
    test.startServer()
    test.drop(3, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK,
              acknowledgement=122)
    test.startClient()
    test.wait(360)
    test.checkDrop()
    test.checkTransfer()
    test.checkClose()
    test.finish()
