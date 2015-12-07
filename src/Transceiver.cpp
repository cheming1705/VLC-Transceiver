/* Tranceiver code for a Visible Light Communication System.
   Part of a Senior Capstone Project at Northeastern University's Electrical
   and Computer Engineering Department.

   Author: Ben Caine
   Date: September 24, 2015
*/

#include "Transceiver.hpp"


Transceiver::Transceiver(SocketConnection &sockconn,
			 ForwardErrorCorrection &fec,
			 RealtimeControl &pru):
  _sock(sockconn), _fec(fec), _pru(pru) {}

const unsigned PACKET_COUNT = 6500;

void Transceiver::Transmit()
{

  // Initializing pru memory
  _pru.OpenMem();
  
  cout << "Starting Transmit" << endl;
  uint8_t buf[FLUSH_SIZE];
  uint8_t packet[PACKET_SIZE];
  int recvlen;
  uint32_t totallen;

  // Get totallen by receiving it first
  recvlen = _sock.Receive(buf, 4);
  totallen = buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
  // Length is number of packets...
  int packet_num = totallen / DATA_SIZE;
  if (totallen % DATA_SIZE != 0)
    packet_num += 1;

  _pru.setLength(PACKET_COUNT);
  cout << "Incoming data length: " << totallen << endl;
  cout << "Packet count: " << packet_num << endl;

  // Send an Ack to let them know we are ready for data
  _sock.Ack();


  uint32_t received = 0;
  unsigned int n = 0;
  int i = 0;
  int packetlen;

  bool first = true;
  // Read in all data from socket and write to mem or backlog
  while(1) {
    recvlen = _sock.Receive(buf, FLUSH_SIZE);
    received += recvlen;

    /*
    // Really bad hack. First 2-3 packets on RX side are corrupted
    // with old data. Sending first 5 packets twice...
    // Assuming all first 5 packets are full...
    if (first) {
      for (i = 0; i < DATA_SIZE * 5; i+= DATA_SIZE) {
	packetlen = DATA_SIZE;
      
	packetize(buf + i, packet, packetlen * 8);

	for (int k = 0; k < PACKET_SIZE; k++)
	  packet[k] = 0xee;

	_pru.push(packet);
	
      }
      first = false;
      }
    */

    for (i = 0; i < recvlen; i+= DATA_SIZE) {
      
      if ((recvlen - i) >= DATA_SIZE)
	packetlen = DATA_SIZE;
      else
	packetlen = recvlen - i;

      packetize(buf + i, packet, packetlen * 8);

      // TODO: REMOVE ONCE WORKING
      for(int k = 0; k < PACKET_SIZE; k++) {
	packet[k] = n;//0x1f;
      }


      // Increase packet number
      n++;
      cout << "Packet Num " << n << endl;

      _pru.push(packet);
    }

    if (received >= totallen) {
      cout << "Socket Transfer is done." << endl;
      break;
    }
  }

  // Set all high for the rest of packets
  memset(packet, 0xFF, PACKET_SIZE);

  for (i = n; i < PACKET_COUNT; i++) {
    _pru.push(packet);
  }

  cout << "Transmitted " << n << " Packets" << endl;

  cout << "Initializing the PRU and starting transmit" << endl;
  _pru.InitPru();
  _pru.Transmit();
  _pru.DisablePru();

  _pru.CloseMem();
  _sock.Close();

  cout << "Transmit Finished" << endl;
}

void Transceiver::Receive() {

  uint8_t packet[PACKET_SIZE];
  uint8_t data[DATA_SIZE];
  uint8_t buf[FLUSH_SIZE];

  int packetlen_bits = 0;
  int packetlen = 0;
  int sendsize = 0;

  int n = 0;
  
  _pru.OpenMem();

  cout << "Waiting for client to connect..." << endl;
  _sock.WaitForClient();

  cout << "Setting up the PRUs to receive..."<< endl;
  _pru.InitPru();
  _pru.Receive();
  // Wait for it to finish
  _pru.DisablePru();

  /*
  // Toss out first 5
  for (int i = 0; i < 6; i++)
    _pru.pop(packet);
  */
  
  int num_packets = _pru.pruCursor() / PACKET_SIZE;

  /*
  // Subtract 5 for our 5 junk packets
  num_packets -= 6;
  */

  int high = 0;

  for (int i = 0; i < PACKET_COUNT; i++) {
    _pru.pop(packet);
    for (int k = 0; k < PACKET_SIZE; k++)
      printf("%02x", packet[k]);

    for (int j = 0; j < PACKET_SIZE; j++)
      high += packet[j] == 0xFF;

    if (high > PACKET_SIZE - 10)
      break;

    packetlen_bits = depacketize(packet, data);
    packetlen = packetlen_bits / 8;

    // If not a multiple of 8, just return an extra byte
    if (packetlen_bits % 8 != 0)
      packetlen += 1;

    // Copy data into buffer
    memcpy(buf + sendsize, data, packetlen);

    sendsize += packetlen;

    if (packetlen_bits % 8 != 0)
      break;

    if (sendsize >= FLUSH_SIZE) {
      cout << "Sending: " << sendsize << " Bytes"<< endl;
      _sock.Send(buf, sendsize);
      sendsize = 0;
      }
  }
  
  cout << "Received: " << n << " Packets" << endl;

  // Send the rest via sockets.
  if (sendsize > 0) {
    cout << "Sent " << sendsize << " bytes" << endl;
    _sock.Send(buf, sendsize);
  }

  // Mark the PRU done and send Done via sockets
  _sock.SendDone();

  // Close the memory and socket fds
  _pru.CloseMem();
  _sock.Close();

  cout << "Receive Finished" << endl;
}
