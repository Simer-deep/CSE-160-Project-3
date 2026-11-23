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

    log = test.outputText()
    droppedAt = log.find("dropped transport packet")
    establishedAt = log.find("Node 1: Server TCP ESTABLISHED", droppedAt)
    test.check(establishedAt > droppedAt,
               "Server did not finish the handshake after the lost ACK")

    recovery = log[droppedAt:establishedAt]
    clientAck = any("Node 4 conn=" in line and "ACK_TX" in line and
                    "ack=121 " in line for line in recovery.splitlines())
    serverRetry = "Node 1 retransmitted TCP control flags=3" in recovery
    test.check(clientAck or serverRetry,
               "No retransmitted ACK or SYN-ACK was observed")
    test.show("Confirmed handshake recovered after the lost ACK")

    test.checkTransfer()
    test.checkClose()
    test.finish()
