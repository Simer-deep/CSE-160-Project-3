from tcp_common import TransportCase, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK

def run():
    test = TransportCase("handshake_ack_loss")
    test.show("Checking recovery after the last handshake ACK is lost")
    test.startServer()
    test.drop(3, CLIENT, SERVER, SOURCE_PORT, SERVER_PORT, ACK,
              acknowledgement=121, count=5)
    test.startClient()
    test.wait(360)
    test.checkDrop()

    log = test.outputText()
    droppedAt = log.find("dropped transport packet")
    establishedAt = log.find("Node 1: Server TCP ESTABLISHED", droppedAt)
    test.check(establishedAt > droppedAt,
               "Server did not finish the handshake after the lost ACK")

    recovery = log[droppedAt:establishedAt]
    
    replacementAck = any(
        "Node 1 TCP receive:" in line and
        "flags=2" in line and
        "ack=121 len=0" in line and
        int(line.split("seq=")[1].split()[0]) >= 411
        for line in recovery.splitlines()
    )
    test.check(replacementAck,
               "Server did not receive a replacement handshake ACK")
    test.show("Confirmed handshake recovered after the lost ACK")

    test.checkTransfer()
    test.checkClose()
    test.finish()
