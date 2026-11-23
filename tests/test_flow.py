from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK

def run():
    test = TransportCase("flow")
    test.show("Checking receiver pause and zero-window recovery")
    test.startServer()
    test.startClient()
    test.wait(1)
    test.pause()
    test.wait(90)
    test.checkZeroWindow()
    test.drop(2, SERVER, CLIENT, SERVER_PORT, SOURCE_PORT, ACK,
              windowMode=2)
    test.resume()
    test.wait(360)
    test.checkDrop()
    test.check("resumed the receiver" in test.outputText(),
               "Receiver did not resume")
    test.checkTransfer()
    test.checkClose()
    test.finish()
