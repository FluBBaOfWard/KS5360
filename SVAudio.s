//
//  SVAudio.s
//  Watara Supervision Sound emulation for GBA/NDS.
//
//  Created by Fredrik Ahlström on 2022-09-11.
//  Copyright © 2022 Fredrik Ahlström. All rights reserved.
//

#ifdef __arm__
#include "SVVideo.i"

	.global svAudioReset
	.global svAudioMixer

	.syntax unified
	.arm

	.section .text
	.align 2
;@----------------------------------------------------------------------------
svAudioReset:				;@ svvptr=r12=pointer to struct
;@----------------------------------------------------------------------------
	mov r0,#0x00000800
	str r0,[svvptr,#ch1Counter]
	str r0,[svvptr,#ch2Counter]
	str r0,[svvptr,#ch3Counter]
	str r0,[svvptr,#ch4Counter]
	mov r0,#0x80000000
	bx lr

;@----------------------------------------------------------------------------
svAudioMixer:				;@ r0=len, r1=dest, r12=svvptr
;@----------------------------------------------------------------------------
	stmfd sp!,{r0,r1,r4-r11,lr}
;@--------------------------
	ldr r10,=vol1_L

	mov r4,#0
	ldrb r2,[svvptr,#wsvCh1Ctrl]
	ldrb r3,[svvptr,#wsvCh1Len]
	cmp r3,#0
	orrne r2,r2,#0x40
	tst r2,#0x40					;@ Ch 1 on?
	and r2,r2,#0xF
//	orr r2,r2,r2,lsl#4
	moveq r2,#0
	strb r4,[r10,#vol1_L-vol1_L]
	strb r2,[r10,#vol1_R-vol1_L]

	ldrb r2,[svvptr,#wsvCh2Ctrl]
	ldrb r3,[svvptr,#wsvCh2Len]
	cmp r3,#0
	orrne r2,r2,#0x40
	tst r2,#0x40					;@ Ch 2 on?
	and r2,r2,#0xF
//	orr r2,r2,r2,lsl#4
	moveq r2,#0
	strb r2,[r10,#vol2_L-vol1_L]
	strb r4,[r10,#vol2_R-vol1_L]

	strb r4,[r10,#vol3_L-vol1_L]
	strb r4,[r10,#vol3_R-vol1_L]

	ldrb r3,[svvptr,#wsvCh4Ctrl]
	ldrb r2,[svvptr,#wsvCh4Len]
	cmp r2,#0
	orrne r3,r3,#2
	ldrb r2,[svvptr,#wsvCh4FreqVol]
	and r2,r2,#0xF
	tst r3,#2						;@ Ch 4 on?
	moveq r2,#0
	tst r3,#4						;@ Ch 4 right?
	movne r4,r2
	tst r3,#8						;@ Ch 4 left?
	moveq r2,#0
	strb r4,[r10,#vol4_L-vol1_L]
	strb r4,[r10,#vol4_R-vol1_L]


	add r2,svvptr,#ch1Counter
	ldmia r2,{r3-r6}
;@--------------------------
	ldrh r2,[svvptr,#wsvCh1Freq]
	mvn r2,r2,lsl#21
	mov r2,r2,lsr#21
	mov r3,r3,lsr#11
	orr r3,r2,r3,lsl#11
;@--------------------------
	ldrh r2,[svvptr,#wsvCh2Freq]
	mvn r2,r2,lsl#21
	mov r2,r2,lsr#21
	mov r4,r4,lsr#11
	orr r4,r2,r4,lsl#11
;@--------------------------
	ldrb r2,[svvptr,#wsvCh3Ctrl]
	mov r5,r5,lsr#11
	orr r5,r2,r5,lsl#11
;@--------------------------
	ldrb r2,[svvptr,#wsvCh4Ctrl]
	mov r6,r6,lsr#11
	orr r6,r2,r6,lsl#11
;@--------------------------

	mov r11,r11
	ldmfd sp,{r0,r1}			;@ r0=len, r1=dest buffer
	mov r0,r0,lsl#2
	b pcmMix
pcmMixReturn:
	add r0,svvptr,#ch1Counter	;@ Counters
	stmia r0,{r3-r6}

	ldmfd sp!,{r0,r1,r4-r11,pc}
;@----------------------------------------------------------------------------

#ifdef NDS
	.section .itcm						;@ For the NDS ARM9
#elif GBA
	.section .iwram, "ax", %progbits	;@ For the GBA
#endif
	.align 2

#define PSGDIVIDE 16
#define PSGADDITION 0x00020000*PSGDIVIDE
#define PSGSWEEPADD 0x00002000*4*PSGDIVIDE
#define PSGNOISEFEED 0x00050001

;@----------------------------------------------------------------------------
;@ r0  = Length
;@ r1  = Destination
;@ r2  = Mixer register
;@ r3  = Channel 1
;@ r4  = Channel 2
;@ r5  = Channel 3
;@ r6  = Channel 4
;@ r10 = Sample pointer
;@ r11 =
;@----------------------------------------------------------------------------
pcmMix:				;@ r0=len, r1=dest, r12=snptr
// IIIVCCCCCCCCCCC000001FFFFFFFFFFF
// I=sampleindex, V=overflow, C=counter, F=frequency
;@----------------------------------------------------------------------------
mixLoop:
	mov r2,#0x80000000
innerMixLoop:
	add r3,r3,#PSGADDITION
	movs r9,r3,lsr#29
	addcs r3,r3,r3,lsl#17
vol1_L:
	mov lr,#0x00				;@ Volume left
vol1_R:
	orrs lr,lr,#0xFF0000		;@ Volume right
	ands r11,r9,#4
	movne r11,#0xFF
	mla r2,lr,r11,r2

	add r4,r4,#PSGADDITION
	movs r9,r4,lsr#29
	addcs r4,r4,r4,lsl#17
vol2_L:
	mov lr,#0x00				;@ Volume left
vol2_R:
	orrs lr,lr,#0xFF0000		;@ Volume right
	ands r11,r9,#4
	movne r11,#0xFF
	mla r2,lr,r11,r2

	add r5,r5,#PSGADDITION
	movs r9,r5,lsr#29
	addcs r5,r5,r5,lsl#17
vol3_L:
	mov lr,#0x00				;@ Volume left
vol3_R:
	orrs lr,lr,#0xFF0000		;@ Volume right
	ldrb r11,[r10,r9,lsr#1]		;@ Channel 3
	tst r9,#1
	moveq r11,r11,lsr#4
	andne r11,r11,#0xF
	mla r2,lr,r11,r2

	add r6,r6,#PSGADDITION
	movs r9,r6,lsr#29
	addcs r6,r6,r6,lsl#17

	movcs lr,r7,lsr#16
	addscs r7,r7,lr,lsl#16
	ldrcs lr,=PSGNOISEFEED
	eorcs r7,r7,lr
	tst r7,#0x80				;@ Noise 4 enabled?
	ldrbeq r11,[r10,r9,lsr#1]	;@ Channel 4
	andsne r11,r7,#0x00000001
	movne r11,#0xFF
	tst r9,#1
	moveq r11,r11,lsr#4
	andne r11,r11,#0xF
vol4_L:
	mov lr,#0x00				;@ Volume left
vol4_R:
	orrs lr,lr,#0xFF0000		;@ Volume right
	mla r2,lr,r11,r2

	sub r0,r0,#1
	tst r0,#3
	bne innerMixLoop

noSweep:
	eor r2,#0x00008000
	cmp r0,#0
	strpl r2,[r1],#4
	bhi mixLoop				;@ ?? cycles according to No$gba

	mov r2,r7,lsr#17
//	strh r2,[svvptr,#wsvNoiseCntr]
	b pcmMixReturn
;@----------------------------------------------------------------------------


#endif // #ifdef __arm__
