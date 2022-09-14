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

	.global svCh1FreqLowW
	.global svCh1FreqHighW
	.global svCh2FreqLowW
	.global svCh2FreqHighW
	.global svCh3LengthW
	.global svCh3ControlW
	.global svCh3TriggerW
	.global svCh4FreqVolW
	.global svCh4ControlW

	.syntax unified
	.arm

	.section .text
	.align 2

#define PSG_DIVIDE 16
#define PSG_ADDITION 0x00020000*PSG_DIVIDE
#define PSG_NOISE_ADD 0x00020000*PSG_DIVIDE
#define PSG_NOISE_FEED 0x6000
#define PSG_NOISE_FEED2 0x60

;@----------------------------------------------------------------------------
svAudioReset:				;@ svvptr=r12=pointer to struct
;@----------------------------------------------------------------------------
	mov r0,#0x00000800
	str r0,[svvptr,#ch1Counter]
	str r0,[svvptr,#ch2Counter]
	str r0,[svvptr,#ch3Counter]
	str r0,[svvptr,#ch4Counter]
	mov r0,#0x4000
	str r0,[svvptr,#ch4LFSR]
	mov r0,#PSG_NOISE_FEED
	str r0,[svvptr,#ch4Feedback]
	bx lr

;@----------------------------------------------------------------------------
svAudioMixer:				;@ r0=len, r1=dest, r12=svvptr
;@----------------------------------------------------------------------------
	stmfd sp!,{r0,r1,r4-r11,lr}
;@--------------------------
	ldr r10,=vol3_L

	ldrb r2,[svvptr,#wsvCh1Ctrl]
	tst r2,#0x40					;@ Ch 1 on?
	ldrbeq r3,[svvptr,#wsvCh1Len]
	cmpeq r3,#0
	and r9,r2,#0xF
	moveq r9,#0

	ldrb r2,[svvptr,#wsvCh2Ctrl]
	tst r2,#0x40					;@ Ch 2 on?
	ldrbeq r3,[svvptr,#wsvCh2Len]
	cmpeq r3,#0
	and r2,r2,#0xF
	orrne r9,r9,r2,lsl#16

	mov r4,#0
	ldrb r3,[svvptr,#wsvCh3Trigg]
	ands r2,r3,#0x80
	movne r2,#0xF
	ldrb r3,[svvptr,#wsvCh3Ctrl]
	tst r3,#4						;@ Ch 3 right?
	movne r4,r2
	tst r3,#8						;@ Ch 3 left?
	moveq r2,#0
	strb r2,[r10,#vol3_L-vol3_L]
	strb r4,[r10,#vol3_R-vol3_L]

	mov r4,#0
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
	strb r2,[r10,#vol4_L-vol3_L]
	strb r4,[r10,#vol4_R-vol3_L]


	add r2,svvptr,#ch1Counter
	ldmia r2,{r3-r8}

	mov r11,r11
	ldmfd sp,{r0,r1}			;@ r0=len, r1=dest buffer
	b pcmMix
pcmMixReturn:
	add r0,svvptr,#ch1Counter	;@ Counters
	stmia r0,{r3-r8}

	ldmfd sp!,{r0,r1,r4-r11,pc}
;@----------------------------------------------------------------------------
svCh1FreqLowW:				;@ 0x2010 Channel 1 Frequency Low
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh1FreqLow]
	b calcCh1Freq
;@----------------------------------------------------------------------------
svCh1FreqHighW:				;@ 0x2011 Channel 1 Frequency High
;@----------------------------------------------------------------------------
	and r1,r1,#0x07
	strb r1,[svvptr,#wsvCh1FreqHigh]
calcCh1Freq:
	ldrh r1,[svvptr,#wsvCh1Freq]
	cmp r1,#0xF
	movmi r1,#0xF
	mvn r1,r1,lsl#20
	mov r1,r1,lsr#20
//	add r1,r1,r1,lsl#17
//	orr r1,r1,#0x800
	ldr r0,[svvptr,#ch1Counter]
//	and r0,r0,#0xE0000000
//	orr r1,r1,r0
	mov r0,r0,lsr#17
	orr r1,r1,r0,lsl#17
	str r1,[svvptr,#ch1Counter]
	bx lr

;@----------------------------------------------------------------------------
svCh2FreqLowW:				;@ 0x2014 Channel 2 Frequency Low
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh2FreqLow]
	b calcCh2Freq
;@----------------------------------------------------------------------------
svCh2FreqHighW:				;@ 0x2015 Channel 2 Frequency High
;@----------------------------------------------------------------------------
	and r1,r1,#0x07
	strb r1,[svvptr,#wsvCh2FreqHigh]
calcCh2Freq:
	ldrh r1,[svvptr,#wsvCh2Freq]
	cmp r1,#0xF
	movmi r1,#0xF
	mvn r1,r1,lsl#20
	mov r1,r1,lsr#20
//	add r1,r1,r1,lsl#17
//	orr r1,r1,#0x800
	ldr r0,[svvptr,#ch2Counter]
//	and r0,r0,#0xE0000000
//	orr r1,r1,r0
	mov r0,r0,lsr#17
	orr r1,r1,r0,lsl#17
	str r1,[svvptr,#ch2Counter]
	bx lr
;@----------------------------------------------------------------------------
svCh3LengthW:				;@ 0x201A Channel 3 Length
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh3Len]
	mov r1,r1,lsl#24
	str r1,[svvptr,#sndDmaLength]
	bx lr
;@----------------------------------------------------------------------------
svCh3ControlW:				;@ 0x201B Channel 3 Control
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh3Ctrl]
	and r1,r1,#3
	mov r0,#0x1000
	mov r0,r0,lsr r1
	str r0,[svvptr,#ch3Counter]
	bx lr
;@----------------------------------------------------------------------------
svCh3TriggerW:				;@ 0x201C Channel 3 Trigger
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh3Trigg]
	ldrh r0,[svvptr,#wsvCh3Adr]
	subs r0,r0,#0x8000
	bxmi lr
	ldr r2,=romSpacePtr
	ldr r2,[r2]
	ldrb r1,[svvptr,#wsvCh3Ctrl]
	and r1,r1,#0x70				;@ Bank register for samples
	add r0,r0,r1,lsl#10
	add r0,r0,r2
	str r0,[svvptr,#ch3Address]
	bx lr
;@----------------------------------------------------------------------------
svCh4FreqVolW:				;@ 0x2028 Channel 4 Frequency & Volume
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh4FreqVol]
	mov r1,r1,lsr#4
	cmp r1,#2					;@ Can't go lower than 2.
	movmi r1,#2
	cmp r1,#0xE
	bicpl r1,r1,#2				;@ E & F are the same as C & D
	mov r0,#-8
	mov r0,r0,lsl r1
	mov r0,r0,lsl#16
	orr r0,r0,r0,lsr#16
	str r0,[svvptr,#ch4Counter]
	bx lr
;@----------------------------------------------------------------------------
svCh4ControlW:				;@ 0x202A Channel 4 Control
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh4Ctrl]
	and r0,r1,#0x10				;@ LFSR enabled?
	tst r1,#1					;@ Tap 7 or 15?
	moveq r0,r0,lsl#2			;@ 0x40
	movne r0,r0,lsl#10			;@ 0x4000
	str r0,[svvptr,#ch4LFSR]
	orr r0,r0,r0,lsr#1
	str r0,[svvptr,#ch4Feedback]
	bx lr

;@----------------------------------------------------------------------------

#ifdef NDS
	.section .itcm						;@ For the NDS ARM9
#elif GBA
	.section .iwram, "ax", %progbits	;@ For the GBA
#endif
	.align 2

;@----------------------------------------------------------------------------
;@ r0  = Length
;@ r1  = Destination
;@ r2  = Mixer register
;@ r3  = Channel 1 wave R
;@ r4  = Channel 2 wave L
;@ r5  = Channel 3 sample
;@ r6  = Channel 4 noise
;@ r7  = Channel 4 LFSR
;@ r8  = Channel 3 Sample Address
;@ r9  = Ch1 & Ch2 volume
;@ r10 =
;@ r11 =
;@----------------------------------------------------------------------------
pcmMix:				;@ r0=len, r1=dest, r12=snptr
// IIIVCCCCCCCCCCC000001FFFFFFFFFFF
// I=sampleindex, V=overflow, C=counter, F=frequency
;@----------------------------------------------------------------------------
	mov r0,r0,lsl#2
mixLoop:
	mov r2,#0x80000000
innerMixLoop:
	add r3,r3,#PSG_ADDITION		;@ Ch1
	movs lr,r3,lsr#29
	addcs r3,r3,r3,lsl#17
	ands lr,lr,#4
	addne r2,r2,r9,lsl#24

	add r4,r4,#PSG_ADDITION		;@ Ch2
	movs lr,r4,lsr#29
	addcs r4,r4,r4,lsl#17
	ands lr,lr,#4
	addne r2,r2,r9,lsr#8

	adds r5,r5,r5,lsl#16
	addcs r8,r8,#1
vol3_L:
	mov lr,#0x00				;@ Volume left
vol3_R:
	orr lr,lr,#0xFF0000			;@ Volume right
	ldrb r11,[r8]				;@ Channel 3
	movmi r11,r11,lsl#4
	and r11,r11,#0xF0
	mla r2,lr,r11,r2

	adds r6,r6,#PSG_NOISE_ADD
	addcs r6,r6,r6,lsl#16
	movscs r7,r7,lsr#1
	ldrcs lr,[svvptr,#ch4Feedback]
	eorcs r7,r7,lr
	tst r7,#0x00000001
vol4_L:
	addne r2,r2,#0xFF00			;@ Volume left
vol4_R:
	addne r2,r2,#0xFF000000		;@ Volume right

	sub r0,r0,#1
	tst r0,#3
	bne innerMixLoop

noSweep:
	eor r2,#0x00008000
	cmp r0,#0
	strpl r2,[r1],#4
	bhi mixLoop				;@ ?? cycles according to No$gba

	b pcmMixReturn
;@----------------------------------------------------------------------------


#endif // #ifdef __arm__
