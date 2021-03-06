#include "Transceiver.hpp"
#include "ForwardErrorCorrection.hpp"
#include "RealtimeControl.hpp"
#include "SocketConnection.hpp"
#include "Golay.hpp"
#include "Util.hpp"
#include "Packetize.hpp"
#include <iostream>
#include <exception>
#include <ctime>
#include <cstdlib>
#include <cstring>

using namespace std;

unsigned char* GenerateData(int bytes) {
    unsigned char *data = new unsigned char[bytes];

    // Generate Alphabet over and over
    for (int i = 0; i < bytes; i++) {
        data[i] = char((i % 26) + 97);
    }

    return data;
}

void CorruptData(unsigned char* data,
                 double p,
                 int bytes) {

    double q;
    for (int i = 0; i < bytes * 8; i++) {
        q = ((double) rand() / (RAND_MAX));
        if (q < p)
            setBit(data, i, getBit(data, i) ^ 1);

    }
}

unsigned int HammingDistance(unsigned char* a,
                             unsigned char* b,
                             unsigned int length) {

    unsigned int num_mismatches = 0;
    for(int n = 0; n < length; n++) {
        for (int i = 0; i < 8; ++i) {
            if (getBit(a + n, i) != getBit(b + n, i)) {
                cout << "N: " << n << " Bit: " << i << endl;
                num_mismatches += 1;
            }
            //num_mismatches += (getBit(a, i) != getBit(b, i));
        }
    }

    return num_mismatches;
}

void TestFEC() {
    int data_length = 96;
    double p_error = 0.06;

    cout << "Testing FEC with P(error) = " << p_error << endl;

    assert(data_length % 3 == 0);

    unsigned char* data = GenerateData(data_length);
    unsigned char* encoded = new unsigned char[data_length * 2];
    unsigned char* decoded = new unsigned char[data_length];

    cout << data << endl;
    cout << "-------------------------" << endl;

    ForwardErrorCorrection fec;

    fec.Encode(data, encoded, data_length);
    CorruptData(encoded, p_error, data_length);
    fec.Decode(encoded, decoded, data_length * 2);

    cout << decoded << endl;

    cout << "Hamming Distance between input and output: ";
    cout << HammingDistance(data, decoded, data_length) << endl;

    assert(HammingDistance(data, decoded, data_length) == 0);
    delete[] data;
    delete[] encoded;
    delete[] decoded;
}

void TestByteQueue() {
    RealtimeControl pru;
    pru.OpenMem();

    uint8_t* in = GenerateData(81);

    pru.push(in);
    pru.setCursor(0);

    uint8_t* out = new uint8_t[81];
    pru.pop(out);

    cout << in << endl;
    cout << out << endl;

    int distance = HammingDistance(in, out, 81);
    cout << "Distance: " << distance << endl;
    assert(distance == 0);
    pru.CloseMem();

    delete [] in;
    delete [] out;
}

void TestManchester() {
    int data_length = 1000;
    unsigned char* data = new unsigned char[data_length];
    unsigned char* encoded = new unsigned char[data_length * 2];
    unsigned char* decoded = new unsigned char[data_length];

    unsigned char val = 0xaa;
    for (int i = 0; i < data_length; i++) {
        data[i] = val;
        if (val == 0xaa)
            val = 0x55;
        else
            val = 0xaa;
    }

    ForwardErrorCorrection fec;

    for(int i = 0; i <  data_length; i++)
        printf("%02x", data[i]);
    cout << endl;
    cout << "---------------------" << endl;
    fec.ManchesterEncode(data, encoded, data_length * 8);

    for(int i = 0; i < data_length * 2; i++)
        printf("%02x", encoded[i]);
    cout << endl;

    cout << "---------------------" << endl;
    fec.ManchesterDecode(encoded, decoded, data_length * 2 * 8);

    for(int i = 0; i <  data_length; i++)
        printf("%02x", decoded[i]);
    cout << endl;

    assert(HammingDistance(data, decoded, 2) == 0);

    delete[] data;
}

void TestBasicPacketization() {

    // Basic test of a normal packet size
    //uint8_t *data = GenerateData(40);
    uint8_t *data = new uint8_t[40];
    uint8_t *packet = new uint8_t[42];
    uint8_t *out = new uint8_t[40];

    for (int i = 0; i < 40; i++)
        data[i] = 'a';

    packetize(data, packet, 40 * 8);

    uint16_t bitlen = depacketize(packet, out);

    cout << "Bitlen: " << bitlen << endl;
    cout << "IN:  " << data << endl;
    cout << "OUT: " << out << endl;

    assert(HammingDistance(data, out, 40) == 0);
    assert(bitlen == 40 * 8);

    delete[] data;
    delete[] packet;
    delete[] out;

}

void TestAdvPacketization() {

    // Test truncated packetization with padding
    uint8_t *data = GenerateData(30);
    uint8_t *packet = new uint8_t[42];
    uint8_t *out = new uint8_t[40];

    packetize(data, packet, 30 * 8);
    uint16_t bitlen = depacketize(packet, out);

    cout << "Bitlen: " << bitlen << endl;
    cout << "IN:  " << data << endl;
    cout << "OUT: " << out << endl;

    assert(HammingDistance(data, out, 30) == 0);
    assert(bitlen = 30 * 8);

    delete[] data;
    delete[] packet;
    delete[] out;
}


void TestDataPipeline() {
    // Generate Data

    int data_length = 1000;
    double p_error = 0.015;
    uint8_t* data = GenerateData(data_length);
    // Packets are all 42 bytes
    uint8_t* packet = new uint8_t[42];
    uint8_t* encoded = new uint8_t[81];
    uint8_t* decoded = new uint8_t[data_length];

    // Encode
    ForwardErrorCorrection fec;
    RealtimeControl pru;

    pru.OpenMem();

    cout << "Created objects" << endl;


    int full_packets = data_length / 40;
    int last_packet_len = data_length % 40;
    int bitlen;

    int num = 0;
    // Loop through data
    for(int i = 0; i < data_length; i+=40) {
        if (full_packets > 0)
            bitlen = 40 * 8;
        else
            bitlen = last_packet_len * 8;

        // First packetize the data...
        packetize(data + i, packet, bitlen);

        // Then encode it...
        fec.Encode(packet, encoded, 42);

        // Corrupt it a bit.. For fun
        CorruptData(encoded, p_error, 81);

        // Then we want to save it to ByteQueue
        pru.push(encoded);
        full_packets -= 1;
        num++;
    }
    cout << "Loaded " << num << " Packets into the ByteQueue" << endl;

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    pru.setCursor(0);

    num = 0;
    int total_len = 0;
    // Reverse this...
    for(int i = 0; i < data_length; i+=40) {
        // Pop 81 Bytes
        pru.pop(encoded);
        fec.Decode(encoded, packet, 81);

        uint16_t len = depacketize(packet, decoded + i);
        total_len += len;
        num ++;
    }

    cout << "Decoded " << num << " Packets." << endl;
    cout << "Decoded data is " << total_len << " Bytes" << endl;

    int hamming_dist = HammingDistance(data, decoded, 1000);

    cout << "Distance between send and received: " << hamming_dist;
    cout << endl;

    assert(hamming_dist == 0);
    pru.CloseMem();
}


void TestDataStorage() {

    RealtimeControl pru;
    pru.OpenMem();

    unsigned int num_packets = 40;
    uint8_t data[81];

    for(unsigned int n = 0; n < num_packets; n++) {
        for (int i = 0; i < 81; i++) {
            data[i] = n;
        }
        pru.push(data);
    }

    pru.setCursor(0);
    memset(data, 0, 81);

    for(unsigned int n = 0; n < num_packets; n++) {
        pru.pop(data);
        for (int i = 0; i < 81; i++)
            assert(n == data[i]);
    }
    cout << "Data Storage Test Passed" << endl;
}


int main() {

    cout << "Forward Error Correction Test Running...\n" << endl;
    TestFEC();

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    cout << "ByteQueue Test Running...\n" << endl;
    TestByteQueue();

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    cout << "Manchester Encoding Test Running...\n" << endl;
    TestManchester();

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    cout << "Basic Packetization Test Running...\n" << endl;
    TestBasicPacketization();

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    cout << "Advanced Packetization Test Running...\n" << endl;
    TestAdvPacketization();

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    cout << "Data Pipeline Test Running...\n" << endl;
    TestDataPipeline();

    cout << "----------------------------------------";
    cout << "----------------------------------------" << endl;

    cout << "Data Storage Test Running...\n" << endl;
    TestDataStorage();

    return 0;
};
