/**
 * @author UCM ANDES Lab
 * $Author: abeltran2 $
 * $LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
 *
 */


#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include <string.h>

module CommandHandlerP {
   provides interface CommandHandler;
   uses interface Receive;
   uses interface Pool<message_t>;
   uses interface Queue<message_t*>;
   uses interface Packet;
}

implementation {
    uint16_t read16(uint8_t* data) {
        return ((uint16_t)data[0] << 8) | data[1];
    }

    uint32_t read32(uint8_t* data) {
        return ((uint32_t)data[0] << 24) |
            ((uint32_t)data[1] << 16) |
            ((uint32_t)data[2] << 8) | data[3];
    }

    task void processCommand() {
        if(!call Queue.empty()) {
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;

            uint8_t pingData[PACKET_MAX_PAYLOAD_SIZE];
            uint8_t copyLen;

            // Pop message out of queue.
            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            // Check to see if the packet is valid.
            if(!payload) {
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }
            // Change it to our type.
            msg = (CommandMsg*) payload;

            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;

            //Find out which command was called and call related command
            switch(commandID) {
            // A ping will have the destination of the packet as the first
            // value and the string in the remainder of the payload
            case CMD_PING:
                dbg(COMMAND_CHANNEL, "Command Type: Ping\n");

                memset(pingData, 0, sizeof(pingData));

                copyLen = sizeof(msg->payload) - 1;

                if(copyLen > PACKET_MAX_PAYLOAD_SIZE) {
                    copyLen = PACKET_MAX_PAYLOAD_SIZE;
                }

                memcpy(pingData, &buff[1], copyLen);

                signal CommandHandler.ping(buff[0], pingData);
                break;

            case CMD_NEIGHBOR_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
                signal CommandHandler.printNeighbors();
                break;

            case CMD_LINKSTATE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
                signal CommandHandler.printLinkState();
                break;

            case CMD_ROUTETABLE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
                signal CommandHandler.printRouteTable();
                break;

            case CMD_TEST_CLIENT:
                signal CommandHandler.setTestClient(read16(buff), buff[2],
                    buff[3], read32(&buff[4]));
                break;

            case CMD_TEST_SERVER:
                signal CommandHandler.setTestServer(buff[0]);
                break;

            case CMD_TEST_EXPECTED:
                signal CommandHandler.setTestExpected(read16(buff), buff[2],
                    buff[3], read32(&buff[4]));
                break;

            case CMD_TEST_CLOSE:
                signal CommandHandler.setTestClose(read16(buff), buff[2], buff[3]);
                break;

            case CMD_TEST_PAUSE:
                signal CommandHandler.setTestPause(read16(buff), buff[2], buff[3]);
                break;

            case CMD_TEST_RESUME:
                signal CommandHandler.setTestResume(read16(buff), buff[2], buff[3]);
                break;

            case CMD_TEST_DROP:
                signal CommandHandler.setTestDrop(read16(buff),
                    read16(&buff[2]), buff[4], buff[5], buff[6],
                    read16(&buff[7]), read16(&buff[9]),
                    buff[11], buff[12]);
                break;

            default:
                dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                break;
            }
            call Pool.put(raw_msg);
        }

        if(!call Queue.empty()) {
            post processCommand();
        }
    }

    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len) {

        if(len != sizeof(CommandMsg)) {
            dbg(COMMAND_CHANNEL, "Invalid command packet size\n");
            return raw_msg;
        }

        if(!call Pool.empty()) {

            call Queue.enqueue(raw_msg);
            post processCommand();

            return call Pool.get();
        }

        return raw_msg;
    }

}
