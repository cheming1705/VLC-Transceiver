// Receiver - PRU0 source code.

// Responsible for sampling incoming data from the input pin (Header 8, 
// Pin 15) and passing it to PRU1 for saving to external RAM. Pin sampling 
// occurs in the same fashion as pin setting (see ../tx/pru0.p), with a few 
// added states. For purposes of both frame and bit synchronization, a preamble 
// is used. When not currently processing a packet, the receiver will sample 
// the input pin at the transmission frequency until it either receives an 
// acceptable number of bits (see REQ_BITS in include/asm.hp) of a valid preamble 
// or times out (see RX_PRU0_TIMEOUT in asm.hp). Upon reception of sufficient 
// preamble bits, frame synchronization is confirmed. In order to bit-synchronize, 
// the receiver will then begin sampling the input pin much more rapidly than the 
// transmission frequency, sampling for a transition to low which is inherent 
// after the 14th bit of the preamble. Sampling much faster than the transmission 
// frequency allows identification of the bit-timing of the incoming stream, and 
// thus allows the receiver to synchronize with this timing at the beginning of each 
// packet. After a packet is identified and synchronized, processing continues in a 
// manner analogous to that of the PRU0 transmitter code (see ../tx/pru0.p).

.origin 0
.entrypoint INIT
#include "../../include/asm.hp"

//  _____________________
//  Register  |  Purpose
//     r0.w0  |  Counter - delay loops performed
//     r0.b2  |  Counter - registers sampled
//     r0.b3  |  Counter - number of bits matching preamble
//     r1.w2  |  Holder  - preamble bitmask
//     r2.w0  |  Holder  - sampled bitstream (preamble)
//     r2.w2  |  Holder  - actual preamble value for comparison
//     r3.w0  |  Counter - preamble timeout
//     r3.w2  |  Holder  - preamble timeout limit
//       r4   |  Holder  - sampled bit
//     r4.w0  |  Holder  - XOR result (preamble)
//     r4.w2  |  Holder  - LSR/AND result (preamble)
//     r5.w0  |  Holder  - bit-sync delay value
//     r5.w2  |  Holder  - backward delay value
//     r6.w0  |  Holder  - bit-check delay value 
//     r6.w2  |  Holder  - forward delay value
//     r7.w0  |  Counter - packets sampled
//     r7.w2  |  Holder  - max packets to sample
//       r8   |  Free
//     r9-r29 |  Holder  - sampled registers
//    r30.t15 |  Holder  - output pin value (debug)
//    r31.t15 |  Holder  - input pin value

INIT:
    
	LBCO      r0, C4, 4, 4
	CLR       r0, r0, 4									 // Enable OCP master port
	SBCO      r0, C4, 4, 4

	MOV       r0, 0x00000120  
	MOV       r1, PRU0CTPPR_0							 // Enable PRU RAM memory access
	SBBO      r0, r1, 0, 4

	MOV       r0.w0, 0                					 // init delay counter to 0
	MOV       r0.b2, 0                					 // init reg number to 0
	MOV       r0.b3, 0                					 // init bit matches counter to 0
	
	MOV       r1.w2, PRE_BITMASK      					 // load value to AND out irrelevant bits

	MOV       r2.w0, INIT_PRE         					 // recent bits holder
    MOV       r2.w2, PREAMBLE         					 // actual preamble holder

	MOV       r3.w0, 0			       					 // init preamble timeout counter to 0
	MOV       r3.w2, RX_PRU0_TIMEOUT  					 // store preamble timeout limit for comparison
	
	MOV       r4.w0, 0                					 // XOR holder
	MOV       r4.w2, 0                					 // LSR/AND holder

	MOV       r5.w0, DELAY_P2_RX      					 // store bit-sync delay value for comparison
	MOV       r5.w2, DELAY_BWD_RX     					 // store backward delay value for comparison

	MOV       r6.w0, DELAY_P1_RX      					 // store bit-check delay value for comparsion
	MOV       r6.w2, DELAY_FWD_RX     					 // store forward delay value for comparison

	MOV       r7.w0, 0                					 // init packet counter to 0
	
	MOV       r8.w0, TRANS_TIMEOUT    					 // store transition timeout for comparison
	
    JMP       P1_SMP                  					 // jump to preamble check

NEW_PACKET:
    XOUT      10, r9, PACK_LEN        					 // write data to PRU1

P1_RESET:
    MOV       r2.w0, INIT_PRE         					 // reset bit holder

P1_SMP: 							   
    MOV       r0.w0, 0                					 // reset delay
    LSL       r2.w0, r2.w0, 1         					 // shift preamble holder to prepare for new bit
    GET_BIT   r31, PIN_OFFSET_BIT, r4 					 // sample input pin
    QBEQ      P1_SET, r4, 1           					 // if bit set, jump to set

P1_CLR:
    CLR_BIT   r2.w0.t0                					 // clear new bit
    MOV       r0.b3, 0                					 // reset verified bits
    JMP       P1_TIMEOUT

P1_SET: 						  
    SET_BIT   r2.w0.t0                					 // set new bit
    MOV       r0.b3, 0                					 // reset verified bits
    JMP       P1_TIMEOUT
	
P1_TIMEOUT:
	MOV       r0.w0, 0 	              					 // NOP
	QBEQ      P1_CHK, r7.w0, 0        					 // if we haven't received a packet yet, don't enforce timeout
    ADD       r3.w0, r3.w0, 1         					 // otherwise, increment timeout counter
    QBEQ      STOP_JMP1, r3.w0, r3.w2 					 // if matches our limit, jump to stop
	MOV       r6.w0, DELAY_RXINPROG   					 // update preamble delay for future packets (which now need to be checked for timeout)
	MOV       r6.w0, DELAY_RXINPROG   				     // NOP
	
P1_CHK:
    GET_DIFF  r2.w0, r2.w2, r0.b3, r4.w0, r4.w2, r1.w2   // get number of matches between preamble and current bitstream
    QBLT      P2_INIT, r0.b3, REQ_BITS                   // if enough bits match, jump to bit-sync

P1_DEL: 
    ADD       r0.w0, r0.w0, 1
    QBNE      P1_DEL, r0.w0, r6.w0     					 // otherwise, delay sufficiently and
	JMP       P1_SMP                    				 // keep sampling

P2_INIT: 
	MOV       r3.w0, 0                        			 // reset preamble timeout counter

P2_SMP: 
	ADD       r0.w0, r0.w0, 1                 			 // incr delay counter
	QBLT      P1_RESET, r0.w0, r8.w0         			 // if taken too long, revert to P stage 1
	GET_BIT   r31, PIN_OFFSET_BIT, r4     				 // sample input pin
	QBNE      P2_SMP, r4, 0                  			 // if pin not reading 0, restart loop
	MOV       r0.w0, 0                        			 // reset delay counter
	
P2_DEL:
	ADD       r0.w0, r0.w0, 1
	QBNE      P2_DEL, r0.w0, r5.w0           			 // delay to middle of first data bit

	MOV       r29.w0, r2.w0                   			 // copy preamble byte 2 into storage reg
	JMP       SMP_B3b1                        			 // jump to normal operation
	
DEL_CPY:
    ADD       r0.w0, r0.w0, 1
    QBNE      DEL_CPY, r0.w0, r5.w2          			 // delay after copying a register

SMP_B1b1:
    MOV       r0.w0, 0
    GET_BIT   r31, PIN_OFFSET_BIT, r4
    QBEQ      SET_B1b1, r4, 1

CLR_B1b1:
	CLR_BIT   r29.t0
	JMP       DEL_B1b1

SET_B1b1:
	SET_BIT   r29.t0
	JMP       DEL_B1b1

DEL_B1b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b1, r0.w0, r6.w2

SMP_B1b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b2, r4, 1

CLR_B1b2:
	CLR_BIT   r29.t1
	JMP       DEL_B1b2

SET_B1b2:
	SET_BIT   r29.t1
	JMP       DEL_B1b2

DEL_B1b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b2, r0.w0, r6.w2

SMP_B1b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b3, r4, 1

CLR_B1b3:
	CLR_BIT   r29.t2
	JMP       DEL_B1b3

SET_B1b3:
	SET_BIT   r29.t2
	JMP       DEL_B1b3

DEL_B1b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b3, r0.w0, r6.w2

SMP_B1b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b4, r4, 1

CLR_B1b4:
	CLR_BIT   r29.t3
	JMP       DEL_B1b4

SET_B1b4:
	SET_BIT   r29.t3
	JMP       DEL_B1b4

DEL_B1b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b4, r0.w0, r6.w2

SMP_B1b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b5, r4, 1

CLR_B1b5:
	CLR_BIT   r29.t4
	JMP       DEL_B1b5

SET_B1b5:
	SET_BIT   r29.t4
	JMP       DEL_B1b5

DEL_B1b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b5, r0.w0, r6.w2

SMP_B1b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b6, r4, 1

CLR_B1b6:
	CLR_BIT   r29.t5
	JMP       DEL_B1b6

SET_B1b6:
	SET_BIT   r29.t5
	JMP       DEL_B1b6

DEL_B1b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b6, r0.w0, r6.w2

SMP_B1b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b7, r4, 1

CLR_B1b7:
	CLR_BIT   r29.t6
	JMP       DEL_B1b7

SET_B1b7:
	SET_BIT   r29.t6
	JMP       DEL_B1b7

DEL_B1b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b7, r0.w0, r6.w2

SMP_B1b8:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B1b8, r4, 1

CLR_B1b8:
	CLR_BIT   r29.t7
	JMP       DEL_B1b8

SET_B1b8:
	SET_BIT   r29.t7
	JMP       DEL_B1b8

BCK_P1b8:
	JMP       NEW_PACKET

BCK_B1b8:
	JMP       DEL_CPY

STOP_JMP1:
	JMP       STOP_JMP2

DEL_B1b8:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B1b8, r0.w0, r6.w2

SMP_B2b1:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b1, r4, 1

CLR_B2b1:
	CLR_BIT   r29.t8
	JMP       DEL_B2b1

SET_B2b1:
	SET_BIT   r29.t8
	JMP       DEL_B2b1

DEL_B2b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b1, r0.w0, r6.w2

SMP_B2b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b2, r4, 1

CLR_B2b2:
	CLR_BIT   r29.t9
	JMP       DEL_B2b2

SET_B2b2:
	SET_BIT   r29.t9
	JMP       DEL_B2b2

DEL_B2b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b2, r0.w0, r6.w2

SMP_B2b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b3, r4, 1

CLR_B2b3:
	CLR_BIT   r29.t10
	JMP       DEL_B2b3

SET_B2b3:
	SET_BIT   r29.t10
	JMP       DEL_B2b3

DEL_B2b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b3, r0.w0, r6.w2

SMP_B2b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b4, r4, 1

CLR_B2b4:
	CLR_BIT   r29.t11
	JMP       DEL_B2b4

SET_B2b4:
	SET_BIT   r29.t11
	JMP       DEL_B2b4

DEL_B2b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b4, r0.w0, r6.w2

SMP_B2b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b5, r4, 1

CLR_B2b5:
	CLR_BIT   r29.t12
	JMP       DEL_B2b5

SET_B2b5:
	SET_BIT   r29.t12
	JMP       DEL_B2b5

DEL_B2b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b5, r0.w0, r6.w2

SMP_B2b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b6, r4, 1

CLR_B2b6:
	CLR_BIT   r29.t13
	JMP       DEL_B2b6

SET_B2b6:
	SET_BIT   r29.t13
	JMP       DEL_B2b6

DEL_B2b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b6, r0.w0, r6.w2

SMP_B2b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b7, r4, 1

CLR_B2b7:
	CLR_BIT   r29.t14
	JMP       DEL_B2b7

SET_B2b7:
	SET_BIT   r29.t14
	JMP       DEL_B2b7

DEL_B2b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b7, r0.w0, r6.w2

SMP_B2b8:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B2b8, r4, 1

CLR_B2b8:
	CLR_BIT   r29.t15
	JMP       DEL_B2b8

SET_B2b8:
	SET_BIT   r29.t15
	JMP       DEL_B2b8

BCK_P2b8:
	JMP       BCK_P1b8

BCK_B2b8:
	JMP       BCK_B1b8

STOP_JMP2:
	JMP       STOP_JMP3

DEL_B2b8:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B2b8, r0.w0, r6.w2

SMP_B3b1:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b1, r4, 1

CLR_B3b1:
	CLR_BIT   r29.t16
	JMP       DEL_B3b1

SET_B3b1:
	SET_BIT   r29.t16
	JMP       DEL_B3b1

DEL_B3b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b1, r0.w0, r6.w2

SMP_B3b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b2, r4, 1

CLR_B3b2:
	CLR_BIT   r29.t17
	JMP       DEL_B3b2

SET_B3b2:
	SET_BIT   r29.t17
	JMP       DEL_B3b2

DEL_B3b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b2, r0.w0, r6.w2

SMP_B3b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b3, r4, 1

CLR_B3b3:
	CLR_BIT   r29.t18
	JMP       DEL_B3b3

SET_B3b3:
	SET_BIT   r29.t18
	JMP       DEL_B3b3

DEL_B3b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b3, r0.w0, r6.w2

SMP_B3b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b4, r4, 1

CLR_B3b4:
	CLR_BIT   r29.t19
	JMP       DEL_B3b4

SET_B3b4:
	SET_BIT   r29.t19
	JMP       DEL_B3b4

DEL_B3b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b4, r0.w0, r6.w2

SMP_B3b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b5, r4, 1

CLR_B3b5:
	CLR_BIT   r29.t20
	JMP       DEL_B3b5

SET_B3b5:
	SET_BIT   r29.t20
	JMP       DEL_B3b5

DEL_B3b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b5, r0.w0, r6.w2

SMP_B3b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b6, r4, 1

CLR_B3b6:
	CLR_BIT   r29.t21
	JMP       DEL_B3b6

SET_B3b6:
	SET_BIT   r29.t21
	JMP       DEL_B3b6

DEL_B3b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b6, r0.w0, r6.w2

SMP_B3b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b7, r4, 1

CLR_B3b7:
	CLR_BIT   r29.t22
	JMP       DEL_B3b7
		
SET_B3b7:
	SET_BIT   r29.t22
	JMP       DEL_B3b7

DEL_B3b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b7, r0.w0, r6.w2

SMP_B3b8:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B3b8, r4, 1

CLR_B3b8:
	CLR_BIT   r29.t23
	JMP       DEL_B3b8

SET_B3b8:
	SET_BIT   r29.t23
	JMP       DEL_B3b8

BCK_P3b8:
	JMP       BCK_P2b8

BCK_B3b8:
	JMP       BCK_B2b8

STOP_JMP3:
	JMP       STOP

DEL_B3b8:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B3b8, r0.w0, r6.w2

SMP_B4b1:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b1, r4, 1

CLR_B4b1:
	CLR_BIT   r29.t24
	JMP       DEL_B4b1

SET_B4b1:
	SET_BIT   r29.t24
	JMP       DEL_B4b1

DEL_B4b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b1, r0.w0, r6.w2

SMP_B4b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b2, r4, 1

CLR_B4b2:
	CLR_BIT   r29.t25
	JMP       DEL_B4b2

SET_B4b2:
	SET_BIT   r29.t25
	JMP       DEL_B4b2

DEL_B4b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b2, r0.w0, r6.w2

SMP_B4b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b3, r4, 1

CLR_B4b3:
	CLR_BIT   r29.t26
	JMP       DEL_B4b3

SET_B4b3:
	SET_BIT   r29.t26
	JMP       DEL_B4b3

DEL_B4b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b3, r0.w0, r6.w2

SMP_B4b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b4, r4, 1

CLR_B4b4:
	CLR_BIT   r29.t27
	JMP       DEL_B4b4

SET_B4b4:
	SET_BIT   r29.t27
	JMP       DEL_B4b4

DEL_B4b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b4, r0.w0, r6.w2

SMP_B4b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b5, r4, 1

CLR_B4b5:
	CLR_BIT   r29.t28
	JMP       DEL_B4b5

SET_B4b5:
	SET_BIT   r29.t28
	JMP       DEL_B4b5

DEL_B4b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b5, r0.w0, r6.w2

SMP_B4b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b6, r4, 1

CLR_B4b6:
	CLR_BIT   r29.t29
	JMP       DEL_B4b6

SET_B4b6:
	SET_BIT   r29.t29
	JMP       DEL_B4b6

DEL_B4b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b6, r0.w0, r6.w2

SMP_B4b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b7, r4, 1

CLR_B4b7:
	CLR_BIT   r29.t30
	JMP       DEL_B4b7

SET_B4b7:
	SET_BIT   r29.t30
	JMP       DEL_B4b7

DEL_B4b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_B4b7, r0.w0, r6.w2

SMP_B4b8: 
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_B4b8, r4, 1

CLR_B4b8: 
	CLR_BIT   r29.t31
	JMP       UPD_R29

SET_B4b8:
	SET_BIT   r29.t31
	JMP       UPD_R29

UPD_R29:
	ADD       r0.b2,   r0.b2, 1
	QBEQ      CPY_R9,  r0.b2, 1
	QBEQ      CPY_R10, r0.b2, 2
	QBEQ      CPY_R11, r0.b2, 3
	QBEQ      CPY_R12, r0.b2, 4
	QBEQ      CPY_R13, r0.b2, 5
	QBEQ      CPY_R14, r0.b2, 6
	QBEQ      CPY_R15, r0.b2, 7
	QBEQ      CPY_R16, r0.b2, 8
	QBEQ      CPY_R17, r0.b2, 9
	QBEQ      CPY_R18, r0.b2, 10
	QBEQ      CPY_R19, r0.b2, 11
	QBEQ      CPY_R20, r0.b2, 12
	QBEQ      CPY_R21, r0.b2, 13
	QBEQ      CPY_R22, r0.b2, 14
	QBEQ      CPY_R23, r0.b2, 15
	QBEQ      CPY_R24, r0.b2, 16
	QBEQ      CPY_R25, r0.b2, 17
	QBEQ      CPY_R26, r0.b2, 18
	QBEQ      CPY_R27, r0.b2, 19
	QBEQ      CPY_R28, r0.b2, 20

CHECK_DONE:
    MOV       r4, READY_CODE			            	 // temporarily overwrite r4 with ready code for storage
    SBCO      r4, CONST_PRUSHAREDRAM, 0, 1          	 // write packet ready code to PRU RAM
    MOV       r0.b2, 0                              	 // reset register counter
    ADD       r7.b0, r7.b0, 1                       	 // increment packet counter
    JMP       BCK_P3b8                              	 // jump back to loop start                 

CPY_R9:
	MOV       r9, r29 	                            	 // copy contents of r9 into r9 (modulation reg)
	MOV       r5.w2, DELAY_BWD_RX                   	 // reset delay
	JMP       BCK_B3b8                              	 // jump back to loop start
CPY_R10:
	MOV       r10, r29
	JMP       BCK_B3b8 
CPY_R11:
	MOV       r11, r29 
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8 
CPY_R12:
	MOV       r12, r29 
	JMP       BCK_B3b8
CPY_R13:
	MOV       r13, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R14:
	MOV       r14, r29
	JMP       BCK_B3b8
CPY_R15:
	MOV       r15, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R16:
	MOV       r16, r29
	JMP       BCK_B3b8
CPY_R17:
	MOV       r17, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R18:
	MOV       r18, r29
	JMP       BCK_B3b8
CPY_R19:
	MOV       r19, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R20:
	MOV       r20, r29
	JMP       BCK_B3b8
CPY_R21:
	MOV       r21, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R22:
	MOV       r22, r29
	JMP       BCK_B3b8
CPY_R23:
	MOV       r23, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R24:
	MOV       r24, r29
	JMP       BCK_B3b8
CPY_R25:
	MOV       r25, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8
CPY_R26:
	MOV       r26, r29
	JMP       BCK_B3b8
CPY_R27:
	MOV       r27, r29
	SUB       r5.w2, r5.w2, 1
	JMP       BCK_B3b8

CPY_R28:
	MOV       r28, r29

SMP_R29:
    MOV       r0.w0, 0
	ADD       r5.w2, r5.w2, 1

DEL_R29:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29, r0.w0, r5.w2
	
SMP_R29_B1b1:
    MOV       r0.w0, 0
    GET_BIT   r31, PIN_OFFSET_BIT, r4
    QBEQ      SET_R29_B1b1, r4, 1

CLR_R29_B1b1:
	CLR_BIT   r29.t0
	JMP       DEL_R29_B1b1

SET_R29_B1b1:
	SET_BIT   r29.t0
	JMP       DEL_R29_B1b1

DEL_R29_B1b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b1, r0.w0, r6.w2

SMP_R29_B1b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b2, r4, 1

CLR_R29_B1b2:
	CLR_BIT   r29.t1
	JMP       DEL_R29_B1b2

SET_R29_B1b2:
	SET_BIT   r29.t1
	JMP       DEL_R29_B1b2

DEL_R29_B1b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b2, r0.w0, r6.w2

SMP_R29_B1b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b3, r4, 1

CLR_R29_B1b3:
	CLR_BIT   r29.t2
	JMP       DEL_R29_B1b3

SET_R29_B1b3:
	SET_BIT   r29.t2
	JMP       DEL_R29_B1b3

DEL_R29_B1b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b3, r0.w0, r6.w2

SMP_R29_B1b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b4, r4, 1

CLR_R29_B1b4:
	CLR_BIT   r29.t3
	JMP       DEL_R29_B1b4

SET_R29_B1b4:
	SET_BIT   r29.t3
	JMP       DEL_R29_B1b4

DEL_R29_B1b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b4, r0.w0, r6.w2

SMP_R29_B1b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b5, r4, 1

CLR_R29_B1b5:
	CLR_BIT   r29.t4
	JMP       DEL_R29_B1b5

SET_R29_B1b5:
	SET_BIT   r29.t4
	JMP       DEL_R29_B1b5

DEL_R29_B1b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b5, r0.w0, r6.w2

SMP_R29_B1b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b6, r4, 1

CLR_R29_B1b6:
	CLR_BIT   r29.t5
	JMP       DEL_R29_B1b6

SET_R29_B1b6:
	SET_BIT   r29.t5
	JMP       DEL_R29_B1b6

DEL_R29_B1b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b6, r0.w0, r6.w2

SMP_R29_B1b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b7, r4, 1

CLR_R29_B1b7:
	CLR_BIT   r29.t6
	JMP       DEL_R29_B1b7

SET_R29_B1b7:
	SET_BIT   r29.t6
	JMP       DEL_R29_B1b7

DEL_R29_B1b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b7, r0.w0, r6.w2

SMP_R29_B1b8:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B1b8, r4, 1

CLR_R29_B1b8:
	CLR_BIT   r29.t7
	JMP       DEL_R29_B1b8

SET_R29_B1b8:
	SET_BIT   r29.t7
	JMP       DEL_R29_B1b8

DEL_R29_B1b8:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B1b8, r0.w0, r6.w2

SMP_R29_B2b1:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b1, r4, 1

CLR_R29_B2b1:
	CLR_BIT   r29.t8
	JMP       DEL_R29_B2b1

SET_R29_B2b1:
	SET_BIT   r29.t8
	JMP       DEL_R29_B2b1

DEL_R29_B2b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b1, r0.w0, r6.w2

SMP_R29_B2b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b2, r4, 1

CLR_R29_B2b2:
	CLR_BIT   r29.t9
	JMP       DEL_R29_B2b2

SET_R29_B2b2:
	SET_BIT   r29.t9
	JMP       DEL_R29_B2b2

DEL_R29_B2b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b2, r0.w0, r6.w2

SMP_R29_B2b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b3, r4, 1

CLR_R29_B2b3:
	CLR_BIT   r29.t10
	JMP       DEL_R29_B2b3

SET_R29_B2b3:
	SET_BIT   r29.t10
	JMP       DEL_R29_B2b3

DEL_R29_B2b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b3, r0.w0, r6.w2

SMP_R29_B2b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b4, r4, 1

CLR_R29_B2b4:
	CLR_BIT   r29.t11
	JMP       DEL_R29_B2b4

SET_R29_B2b4:
	SET_BIT   r29.t11
	JMP       DEL_R29_B2b4

DEL_R29_B2b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b4, r0.w0, r6.w2

SMP_R29_B2b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b5, r4, 1

CLR_R29_B2b5:
	CLR_BIT   r29.t12
	JMP       DEL_R29_B2b5

SET_R29_B2b5:
	SET_BIT   r29.t12
	JMP       DEL_R29_B2b5

DEL_R29_B2b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b5, r0.w0, r6.w2

SMP_R29_B2b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b6, r4, 1

CLR_R29_B2b6:
	CLR_BIT   r29.t13
	JMP       DEL_R29_B2b6

SET_R29_B2b6:
	SET_BIT   r29.t13
	JMP       DEL_R29_B2b6

DEL_R29_B2b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b6, r0.w0, r6.w2

SMP_R29_B2b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b7, r4, 1

CLR_R29_B2b7:
	CLR_BIT   r29.t14
	JMP       DEL_R29_B2b7

SET_R29_B2b7:
	SET_BIT   r29.t14
	JMP       DEL_R29_B2b7

DEL_R29_B2b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b7, r0.w0, r6.w2

SMP_R29_B2b8:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B2b8, r4, 1

CLR_R29_B2b8:
	CLR_BIT   r29.t15
	JMP       DEL_R29_B2b8

SET_R29_B2b8:
	SET_BIT   r29.t15
	JMP       DEL_R29_B2b8

DEL_R29_B2b8:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B2b8, r0.w0, r6.w2

SMP_R29_B3b1:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b1, r4, 1

CLR_R29_B3b1:
	CLR_BIT   r29.t16
	JMP       DEL_R29_B3b1

SET_R29_B3b1:
	SET_BIT   r29.t16
	JMP       DEL_R29_B3b1

DEL_R29_B3b1:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b1, r0.w0, r6.w2

SMP_R29_B3b2:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b2, r4, 1

CLR_R29_B3b2:
	CLR_BIT   r29.t17
	JMP       DEL_R29_B3b2

SET_R29_B3b2:
	SET_BIT   r29.t17
	JMP       DEL_R29_B3b2

DEL_R29_B3b2:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b2, r0.w0, r6.w2

SMP_R29_B3b3:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b3, r4, 1

CLR_R29_B3b3:
	CLR_BIT   r29.t18
	JMP       DEL_R29_B3b3

SET_R29_B3b3:
	SET_BIT   r29.t18
	JMP       DEL_R29_B3b3

DEL_R29_B3b3:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b3, r0.w0, r6.w2

SMP_R29_B3b4:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b4, r4, 1

CLR_R29_B3b4:
	CLR_BIT   r29.t19
	JMP       DEL_R29_B3b4

SET_R29_B3b4:
	SET_BIT   r29.t19
	JMP       DEL_R29_B3b4

DEL_R29_B3b4:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b4, r0.w0, r6.w2

SMP_R29_B3b5:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b5, r4, 1

CLR_R29_B3b5:
	CLR_BIT   r29.t20
	JMP       DEL_R29_B3b5

SET_R29_B3b5:
	SET_BIT   r29.t20
	JMP       DEL_R29_B3b5

DEL_R29_B3b5:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b5, r0.w0, r6.w2

SMP_R29_B3b6:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b6, r4, 1

CLR_R29_B3b6:
	CLR_BIT   r29.t21
	JMP       DEL_R29_B3b6

SET_R29_B3b6:
	SET_BIT   r29.t21
	JMP       DEL_R29_B3b6

DEL_R29_B3b6:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b6, r0.w0, r6.w2

SMP_R29_B3b7:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b7, r4, 1

CLR_R29_B3b7:
	CLR_BIT   r29.t22
	JMP       DEL_R29_B3b7
		
SET_R29_B3b7:
	SET_BIT   r29.t22
	JMP       DEL_R29_B3b7

DEL_R29_B3b7:
	ADD       r0.w0, r0.w0, 1
	QBNE      DEL_R29_B3b7, r0.w0, r6.w2

SMP_R29_B3b8:
	MOV       r0.w0, 0
	GET_BIT   r31, PIN_OFFSET_BIT, r4
	QBEQ      SET_R29_B3b8, r4, 1

CLR_R29_B3b8:
	CLR_BIT   r29.t23
	JMP       CHECK_DONE

SET_R29_B3b8:
	SET_BIT   r29.t23
	JMP       CHECK_DONE
STOP:

	SET       r30.t15                         		 	 // leave output high
	MOV       r31.b0, PRU0_ARM_INTERRUPT + 16   		 // send program completion interrupt to host
	HALT                                      			 // shutdown
