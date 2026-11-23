from tcp_common import TransportCase, basicTransfer

def run():
    test = TransportCase("baseline")
    test.show("Checking a normal 1025-byte transfer")
    basicTransfer(test)
