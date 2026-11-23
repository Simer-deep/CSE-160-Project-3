#include "../../includes/transport.h"

module CongestionControlP {
    provides interface CongestionControl;
}

implementation {
    enum {
        CC_SEGMENT = TRANSPORT_MAX_DATA_SIZE,
        CC_MAX_WINDOW = TRANSPORT_SEND_WINDOW
    };

    void report(socket_store_t* socket, char* reason) {
        dbg("Project3TGen",
            "CC node=%u port=%u cwnd=%u ssthresh=%u reason=%s\n",
            TOS_NODE_ID, socket->localPort,
            socket->cwnd, socket->ssthresh, reason);
    }

    command void CongestionControl.start(socket_store_t* socket) {
        if(socket == NULL) {
            return;
        }

        socket->cwnd = CC_SEGMENT;
        socket->ssthresh = CC_MAX_WINDOW;
        socket->congestionAckCredit = 0;
        report(socket, "start");
    }

    command void CongestionControl.acknowledged(
        socket_store_t* socket, uint16_t bytes) {
        uint16_t increase;

        if(socket == NULL || bytes == 0) {
            return;
        }

        if(socket->cwnd < socket->ssthresh) {
            increase = bytes;
            if(increase > CC_MAX_WINDOW - socket->cwnd) {
                increase = CC_MAX_WINDOW - socket->cwnd;
            }
            socket->cwnd += increase;
        } else if(socket->cwnd < CC_MAX_WINDOW) {
            socket->congestionAckCredit += bytes;
            if(socket->congestionAckCredit >= socket->cwnd) {
                socket->congestionAckCredit -= socket->cwnd;
                socket->cwnd += CC_SEGMENT;
                if(socket->cwnd > CC_MAX_WINDOW) {
                    socket->cwnd = CC_MAX_WINDOW;
                }
            }
        }

        report(socket, "ack");
    }

    command void CongestionControl.timedOut(socket_store_t* socket) {
        uint16_t half;

        if(socket == NULL) {
            return;
        }

        half = socket->cwnd / 2;
        if(half < CC_SEGMENT) {
            half = CC_SEGMENT;
        }

        socket->ssthresh = half;
        socket->cwnd = CC_SEGMENT;
        socket->congestionAckCredit = 0;
        report(socket, "timeout");
    }

    command uint16_t CongestionControl.window(socket_store_t* socket) {
        if(socket == NULL) {
            return CC_SEGMENT;
        }
        return socket->cwnd;
    }
}
