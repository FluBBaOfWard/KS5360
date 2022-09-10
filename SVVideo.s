//
//  SVVideo.s
//  Watara Supervision video emulation for GBA/NDS.
//
//  Created by Fredrik Ahlström on 2004-11-30.
//  Copyright © 2004-2022 Fredrik Ahlström. All rights reserved.
//

#ifdef __arm__

#ifdef GBA
	#include "../Shared/gba_asm.h"
#elif NDS
	#include "../Shared/nds_asm.h"
#endif
#include "SVVideo.i"
#include "../ARM6502/M6502.i"

#define CYCLE_PSL (246*2)

	.global svVideoInit
	.global svVideoReset
	.global svVideoSaveState
	.global svVideoLoadState
	.global svVideoGetStateSize
	.global svDoScanline
	.global copyScrollValues
	.global svConvertScreen
	.global svBufferWindows
	.global svRead
	.global svWrite
	.global svRefW
	.global svGetInterruptVector

	.syntax unified
	.arm

#if GBA
	.section .ewram, "ax", %progbits	;@ For the GBA
#else
	.section .text						;@ For anything else
#endif
	.align 2
;@----------------------------------------------------------------------------
svVideoInit:				;@ Only need to be called once
;@----------------------------------------------------------------------------
	mov r1,#0xffffff00			;@ Build chr decode tbl
	ldr r3,=CHR_DECODE			;@ 0x200
chrLutLoop:
	and r0,r1,#0x03
	and r2,r1,#0x0C
	orr r0,r0,r2,lsl#2
	and r2,r1,#0x30
	orr r0,r0,r2,lsl#4
	and r2,r1,#0xC0
	orr r0,r0,r2,lsl#6
	strh r0,[r3],#2
	adds r1,r1,#1
	bne chrLutLoop

;@----------------------------------------------------------------------------
makeTileBgr:
;@----------------------------------------------------------------------------
	mov r1,#BG_GFX
	mov r0,#0
	mov r2,#32*22
bgrLoop:
	strh r0,[r1],#2
	add r0,r0,#1
	subs r2,r2,#1
	bne bgrLoop

	bx lr
;@----------------------------------------------------------------------------
svVideoReset:		;@ r0=NmiFunc, r1=IrqFunc, r2=ram+LUTs, r3=SOC 0=mono,1=color,2=crystal, r12=svvptr
;@----------------------------------------------------------------------------
	stmfd sp!,{r0-r3,lr}

	mov r0,svvptr
	ldr r1,=ks5360Size/4
	bl memclr_					;@ Clear KS5360 state

	ldr r2,=lineStateTable
	ldr r1,[r2],#4
	mov r0,#-1
	stmia svvptr,{r0-r2}		;@ Reset scanline, nextChange & lineState

	ldmfd sp!,{r0-r3,lr}
	cmp r0,#0
	adreq r0,dummyIrqFunc
	str r0,[svvptr,#nmiFunction]
	cmp r1,#0
	adreq r1,dummyIrqFunc
	str r1,[svvptr,#irqFunction]

	str r2,[svvptr,#gfxRAM]
	ldr r0,=SCROLL_BUFF
	str r0,[svvptr,#scrollBuff]

	strb r3,[svvptr,#wsvSOC]

	b svRegistersReset

dummyIrqFunc:
	bx lr
;@----------------------------------------------------------------------------
_debugIOUnmappedR:
;@----------------------------------------------------------------------------
	ldr r3,=debugIOUnmappedR
	bx r3
;@----------------------------------------------------------------------------
_debugIOUnimplR:
;@----------------------------------------------------------------------------
	ldr r3,=debugIOUnimplR
	bx r3
;@----------------------------------------------------------------------------
_debugIOUnmappedW:
;@----------------------------------------------------------------------------
	ldr r3,=debugIOUnmappedW
	bx r3
;@----------------------------------------------------------------------------
memCopy:
;@----------------------------------------------------------------------------
	ldr r3,=memcpy
;@----------------------------------------------------------------------------
thumbCallR3:
;@----------------------------------------------------------------------------
	bx r3
;@----------------------------------------------------------------------------
svRegistersReset:				;@ in r3=SOC
;@----------------------------------------------------------------------------
	adr r1,IO_Default
	mov r2,#0x30
	add r0,svvptr,#wsvRegs
	stmfd sp!,{svvptr,lr}
	bl memCopy
	ldmfd sp!,{svvptr,lr}
	ldrb r1,[svvptr,#wsvLCDYSize]
	b svRefW

;@----------------------------------------------------------------------------
IO_Default:
	.byte 0xA0, 0xA0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

;@----------------------------------------------------------------------------
svVideoSaveState:		;@ In r0=destination, r1=svvptr. Out r0=state size.
	.type	svVideoSaveState STT_FUNC
;@----------------------------------------------------------------------------
	stmfd sp!,{r4,r5,lr}
	mov r4,r0					;@ Store destination
	mov r5,r1					;@ Store svvptr (r1)

	add r1,r5,#ks5360State
	mov r2,#ks5360StateEnd-ks5360State
	bl memCopy

	ldmfd sp!,{r4,r5,lr}
	mov r0,#ks5360StateEnd-ks5360State
	bx lr
;@----------------------------------------------------------------------------
svVideoLoadState:		;@ In r0=svvptr, r1=source. Out r0=state size.
	.type	svVideoLoadState STT_FUNC
;@----------------------------------------------------------------------------
	stmfd sp!,{r4,r5,lr}
	mov r5,r0					;@ Store svvptr (r0)
	mov r4,r1					;@ Store source

	add r0,r5,#ks5360State
	mov r2,#ks5360StateEnd-ks5360State
	bl memCopy

	bl clearDirtyTiles

	bl reBankSwitch89AB
	bl reBankSwitchCDEF

	ldmfd sp!,{r4,r5,lr}
;@----------------------------------------------------------------------------
svVideoGetStateSize:	;@ Out r0=state size.
	.type	svVideoGetStateSize STT_FUNC
;@----------------------------------------------------------------------------
	mov r0,#ks5360StateEnd-ks5360State
	bx lr

	.pool
;@----------------------------------------------------------------------------
svBufferWindows:
;@----------------------------------------------------------------------------
//	ldr r0,[svvptr,#wsvFgWinXPos]	;@ Win pos/size
	ldr r0,=0xA0A00000
	and r1,r0,#0x000000FF		;@ H start
	and r2,r0,#0x00FF0000		;@ H end
	cmp r1,#GAME_WIDTH
	movpl r1,#GAME_WIDTH
	add r1,r1,#(SCREEN_WIDTH-GAME_WIDTH)/2
	add r2,r2,#0x10000
	cmp r2,#GAME_WIDTH<<16
	movpl r2,#GAME_WIDTH<<16
	add r2,r2,#((SCREEN_WIDTH-GAME_WIDTH)/2)<<16
	cmp r2,r1,lsl#16
	orr r1,r1,r2,lsl#8
	mov r1,r1,ror#24
	movmi r1,#0
	strh r1,[svvptr,#windowData]

	and r1,r0,#0x0000FF00		;@ V start
	mov r2,r0,lsr#24			;@ V end
	cmp r1,#GAME_HEIGHT<<8
	movpl r1,#GAME_HEIGHT<<8
	add r1,r1,#((SCREEN_HEIGHT-GAME_HEIGHT)/2)<<8
	add r2,r2,#1
	cmp r2,#GAME_HEIGHT
	movpl r2,#GAME_HEIGHT
	add r2,r2,#(SCREEN_HEIGHT-GAME_HEIGHT)/2
	cmp r2,r1,lsr#8
	orr r1,r1,r2
	movmi r1,#0
	strh r1,[svvptr,#windowData+2]

	bx lr

;@----------------------------------------------------------------------------
svRead:		;@ I/O read
;@----------------------------------------------------------------------------
	sub r2,r0,#0x2000
	cmp r2,#0x30
	ldrmi pc,[pc,r2,lsl#2]
	b svUnmappedR
io_read_tbl:
	.long svUnknownR		;@ 0x2000
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR		;@ 0x2008
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR		;@ 0x2010
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR		;@ 0x2018
	.long svUnknownR
	.long _201Ar
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long joy0_R			;@ 2020 joypad
	.long svLinkPortDDRR	;@ 2021 Link Port DDR
	.long svLinkPortDataR	;@ 2022 Link Port Data
	.long svTimerValueR		;@ 2023 Timer Value
	.long svTimerIRQClear	;@ 2024 Timer IRQ Clear
	.long svDMAIRQClear		;@ 2025 DMA IRQ Clear
	.long _2026r			;@ System Control
	.long _2027r			;@ IRQ Status
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR
	.long svUnknownR

;@----------------------------------------------------------------------------
svUnmappedR:
;@----------------------------------------------------------------------------
	mov r11,r11					;@ No$GBA breakpoint
	stmfd sp!,{svvptr,lr}
	bl _debugIOUnmappedR
	ldmfd sp!,{svvptr,lr}
	mov r0,#0x00
	bx lr
;@----------------------------------------------------------------------------
svUnknownR:
;@----------------------------------------------------------------------------
	ldr r2,=0x826EBAD0
;@----------------------------------------------------------------------------
svImportantR:
	mov r11,r11					;@ No$GBA breakpoint
	stmfd sp!,{r0,svvptr,lr}
	bl _debugIOUnimplR
	ldmfd sp!,{r0,svvptr,lr}
;@----------------------------------------------------------------------------
svRegR:
	and r0,r0,#0xFF
	add r2,svvptr,#wsvRegs
	ldrb r0,[r2,r0]
	bx lr
	.pool

;@----------------------------------------------------------------------------
_201Ar:		;@ Channel 3 Length
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#sndDmaLength+3]
	bx lr
;@----------------------------------------------------------------------------
svLinkPortDDRR:		;@ 2021
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
svLinkPortDataR:	;@ 2022
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvLinkPortVal]
	bx lr
;@----------------------------------------------------------------------------
svTimerValueR:		;@ 2023
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvTimerValue+3]
	bx lr
;@----------------------------------------------------------------------------
svTimerIRQClear:	;@ 2024
;@----------------------------------------------------------------------------
	stmfd sp!,{lr}
	ldrb r0,[svvptr,#wsvIRQStatus]
	bic r0,r0,#1
	bl svSetInterruptStatus
	mov r0,#0
	ldmfd sp!,{lr}
	bx lr
;@----------------------------------------------------------------------------
svDMAIRQClear:		;@ 2025
;@----------------------------------------------------------------------------
	stmfd sp!,{lr}
	ldrb r0,[svvptr,#wsvIRQStatus]
	bic r0,r0,#2
	bl svSetInterruptStatus
	mov r0,#0
	ldmfd sp!,{lr}
	bx lr
;@----------------------------------------------------------------------------
_2026r:		;@ LCD & IRQs
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvSystemControl]
	bx lr
;@----------------------------------------------------------------------------
_2027r:		;@ IRQ bits
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvIRQStatus]
	bx lr

;@----------------------------------------------------------------------------
svWrite:	;@ I/O write
;@----------------------------------------------------------------------------
	sub r2,r0,#0x2000
	cmp r2,#0x30
	ldrmi pc,[pc,r2,lsl#2]
	b wsvUnmappedW
io_write_tbl:
	.long _2000w			;@ Horizontal screen size
	.long _2001w			;@ Vertical screen size
	.long _2002w			;@ Horizontal scroll
	.long _2003w			;@ Vertical scroll
	.long _2000w
	.long _2001w
	.long _2002w
	.long _2003w
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvDMACtrlW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvRegW			;@ Sound...
	.long wsvRegW
	.long wsvRegW
	.long wsvRegW
	.long wsvRegW
	.long wsvRegW
	.long wsvRegW
	.long wsvRegW
	.long wsvImportantW
	.long wsvImportantW
	.long _201Aw
	.long wsvImportantW
	.long wsvRegW			;@ Sound DMA trigger
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long _2021w			;@ IO port DDR
	.long _2022w			;@ IO port data
	.long wsvTimerValueW	;@ Timer value
	.long wsvTimerIRQClearW	;@ Timer IRQ clear
	.long wsvSoundIRQClearW	;@ Sound IRQ clear
	.long _2026w			;@ LCD & IRQs
	.long wsvUnmappedW
	.long wsvImportantW		;@ Sound DMA...
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW
	.long wsvImportantW

;@----------------------------------------------------------------------------
wsvUnknownW:
;@----------------------------------------------------------------------------
wsvImportantW:
;@----------------------------------------------------------------------------
	and r0,r0,#0xFF
	add r2,svvptr,#wsvRegs
	strb r1,[r2,r0]
	ldr r2,=debugIOUnimplW
	bx r2
;@----------------------------------------------------------------------------
wsvReadOnlyW:
;@----------------------------------------------------------------------------
wsvUnmappedW:
;@----------------------------------------------------------------------------
	b _debugIOUnmappedW
;@----------------------------------------------------------------------------
wsvRegW:
	and r0,r0,#0xFF
	add r2,svvptr,#wsvRegs
	strb r1,[r2,r0]
	bx lr

;@----------------------------------------------------------------------------
_2000w:
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvLCDXSize]
	bx lr
;@----------------------------------------------------------------------------
_2001w:
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
svRefW:						;@ 0x2001, Last scan line.
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvLCDYSize]
	cmp r1,#0x9E
	movmi r1,#0x9E
	cmp r1,#0xC8
	movpl r1,#0xC8
	add r1,r1,#1
	str r1,lineStateLastLine
	mov r0,r1
	b setScreenRefresh

;@----------------------------------------------------------------------------
_2002w:
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvXScroll]
	bx lr
;@----------------------------------------------------------------------------
_2003w:
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvYScroll]
	bx lr
;@----------------------------------------------------------------------------
wsvDMACtrlW:				;@ 0x200D
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvDMACtrl]
	tst r1,#0x80				;@ Start?
	bxeq lr

	stmfd sp!,{r4-r7,lr}
	mov r7,svvptr
	ldrh r4,[svvptr,#wsvDMACBus]
	mov r4,r4,lsl#16

	ldrh r5,[svvptr,#wsvDMAVBus];@ r5=destination
	mov r5,r5,ror#13

	ldrb r6,[svvptr,#wsvDMALen]	;@ r6=length
	mov r6,r6,lsl#24
	sub cycles,cycles,r6,lsl#CYC_SHIFT
	tst r5,#2					;@ From VBus to CBus?
	beq dmaFromVRAMLoop

dmaToVRAMLoop:
	mov addy,r4,lsr#16
	bl memRead8
	add r1,m6502zpage,#0x2000
	strb r0,[r1,r5,lsr#19]
	add r4,r4,#0x10000
	add r5,r5,#0x80000
	subs r6,r6,#0x00100000
	bne dmaToVRAMLoop
	b dmaEnd

dmaFromVRAMLoop:
	add r1,m6502zpage,#0x2000
	ldrb r0,[r1,r5,lsr#19]
	mov addy,r4,lsr#16
	bl memWrite8
	add r4,r4,#0x10000
	add r5,r5,#0x80000
	subs r6,r6,#0x00100000
	bne dmaFromVRAMLoop

dmaEnd:
	mov svvptr,r7
	mov r4,r4,lsr#16
	strh r4,[svvptr,#wsvDMACBus]
	mov r5,r5,ror#19
	strh r5,[svvptr,#wsvDMAVBus]

	mov r6,r6,lsr#24
	strb r6,[svvptr,#wsvDMALen]
	mov r0,#0x00
	strb r0,[svvptr,#wsvDMACtrl]

	ldmfd sp!,{r4-r7,lr}
	bx lr

;@----------------------------------------------------------------------------
_200Ew:		;@ TV link palette?
_200Fw:		;@ TV link something
	bx lr

;@----------------------------------------------------------------------------
_201Aw:		;@ Channel 3 Length
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvCh3Len]
	mov r1,r1,lsl#24
	str r1,[svvptr,#sndDmaLength]
	bx lr
;@----------------------------------------------------------------------------
_2021w:		;@ Link Port DDR write
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvLinkPortDDR]
	b handleLinkPort
;@----------------------------------------------------------------------------
_2022w:		;@ Link Port Data write
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvLinkPortData]
	b handleLinkPort
;@----------------------------------------------------------------------------
wsvTimerValueW:		;@ 0x2023
;@----------------------------------------------------------------------------
	strb r1,[svvptr,#wsvIRQTimer]
	strb r1,[svvptr,#wsvTimerValue+3]
	bx lr
;@----------------------------------------------------------------------------
wsvTimerIRQClearW:	;@ 0x2024
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvIRQStatus]
	bic r0,r0,#1
	b svSetInterruptStatus
;@----------------------------------------------------------------------------
wsvSoundIRQClearW:	;@ 0x2025
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvIRQStatus]
	bic r0,r0,#2
	b svSetInterruptStatus
;@----------------------------------------------------------------------------
_2026w:		;@ LCD & IRQs
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvSystemControl]
	strb r1,[svvptr,#wsvSystemControl]
	eor r0,r0,r1
	tst r0,#0xE0
	stmfd sp!,{lr}
	blne memoryMap89AB
	ldrb r0,[svvptr,#wsvIRQStatus]
	bl svUpdateIrqEnable
	ldmfd sp!,{lr}
	ldrb r0,[svvptr,#wsvSystemControl]

	mov r1,#0x2840		;@ WIN0, BG2 enable. DISPCNTBUFF startvalue. 0x2840
	tst r0,#0x08		;@ lcd en?
	orrne r1,r1,#0x0100

	adr r2,ctrl1Old
	swp r0,r1,[r2]		;@ r0=lastval

	adr r2,ctrl1Line
	ldr addy,[svvptr,#scanline]	;@ addy=scanline
	cmp addy,#159
	movhi addy,#159
	swp r1,addy,[r2]	;@ r1=lastline, lastline=scanline
ctrl1Finish:
//	ldr r2,=DISPCNTBUFF
	add r1,r2,r1,lsl#1
	add r2,r2,addy,lsl#1
ct1:
//	strh r0,[r2],#-2	;@ Fill backwards from scanline to lastline
//	cmp r2,r1
//	bpl ct1

	bx lr

ctrl1Old:	.long 0x2840	;@ Last write
ctrl1Line:	.long 0 		;@ When?


;@----------------------------------------------------------------------------
handleLinkPort:
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvLinkPortData]
	ldrb r1,[svvptr,#wsvLinkPortDDR]
	orr r0,r0,r1
	strb r0,[svvptr,#wsvLinkPortVal]
	ldrb r1,[svvptr,#wsvSystemControl]
;@----------------------------------------------------------------------------
memoryMap89AB:
;@----------------------------------------------------------------------------
	ldrb r0,[svvptr,#wsvLinkPortVal]
	b bankSwitchCart
;@----------------------------------------------------------------------------
newFrame:					;@ Called before line 0
;@----------------------------------------------------------------------------
	bx lr
;@----------------------------------------------------------------------------
endFrame:
;@----------------------------------------------------------------------------
	stmfd sp!,{lr}
//	ldr r2,[svvptr,#wsvBgXScroll]
//	bl scrollCnt
	bl endFrameGfx

	ldmfd sp!,{pc}

;@----------------------------------------------------------------------------
frameEndHook:
	mov r0,#0
	str r0,[svvptr,#scrollLine]

	adr r2,lineStateTable
	ldr r1,[r2],#4
	mov r0,#-1
	stmia svvptr,{r0-r2}		;@ Reset scanline, nextChange & lineState
	bx lr

;@----------------------------------------------------------------------------
lineStateTable:
	.long 0, newFrame			;@ zeroLine
	.long 159, endFrame			;@ After last visible scanline
lineStateLastLine:
	.long 160, frameEndHook		;@ totalScanlines
;@----------------------------------------------------------------------------
#ifdef GBA
	.section .iwram, "ax", %progbits	;@ For the GBA
	.align 2
#endif
;@----------------------------------------------------------------------------
redoScanline:
;@----------------------------------------------------------------------------
	ldr r2,[svvptr,#lineState]
	ldmia r2!,{r0,r1}
	stmib svvptr,{r1,r2}		;@ Write nextLineChange & lineState
	stmfd sp!,{lr}
	mov lr,pc
	bx r0
	ldmfd sp!,{lr}
;@----------------------------------------------------------------------------
svDoScanline:
;@----------------------------------------------------------------------------
	ldmia svvptr,{r0,r1}		;@ Read scanLine & nextLineChange
	add r0,r0,#1
	cmp r0,r1
	bpl redoScanline
	str r0,[svvptr,#scanline]
;@----------------------------------------------------------------------------
checkScanlineIRQ:
;@----------------------------------------------------------------------------
	stmfd sp!,{lr}

	ldr r1,[svvptr,#wsvTimerValue]
	tst r1,#0xFF000000
	beq noTimerCount
	ldrb r2,[svvptr,#wsvSystemControl]
	tst r2,#0x10
	moveq r0,#CYCLE_PSL<<16
	movne r0,#CYCLE_PSL<<10
	subs r1,r1,r0
	biccc r1,r1,#0xFF000000
	tst r1,#0xFF000000
	str r1,[svvptr,#wsvTimerValue]
	ldrb r0,[svvptr,#wsvIRQStatus]
	orreq r0,r0,#0x01				;@ #0 = Timer IRQ
	bl svSetInterruptStatus
noTimerCount:

	ldr r1,[svvptr,#wsvNMITimer]
	adds r1,r1,CYCLE_PSL<<16
	str r1,[svvptr,#wsvNMITimer]
	ldrb r0,[svvptr,#wsvNMIStatus]
	orrcs r0,r0,#1
	bicvs r0,r0,#1
	bl svSetNMIStatus

	ldrb r0,[svvptr,#wsvCh3Trigg]
	tst r0,#0x80
	beq noSoundDMA
	ldr r0,[svvptr,#sndDmaCounter]
	ldrb r2,[svvptr,#wsvCh3Ctrl]
	mov r1,CYCLE_PSL<<23
	and r2,r2,#3				;@ Sound DMA speed
	subs r0,r0,r1,lsr r2
	str r0,[svvptr,#sndDmaCounter]
	bcs noSoundDMA
	ldr r0,[svvptr,#sndDmaLength]
	subs r0,r0,#0x00100000
	str r0,[svvptr,#sndDmaLength]
	bne noSoundDMA
	strb r0,[svvptr,#wsvCh3Trigg]
	ldrb r0,[svvptr,#wsvIRQStatus]
	orr r0,r0,#0x02				;@ #1 = Sound IRQ
	bl svSetInterruptStatus
noSoundDMA:

	ldr r0,[svvptr,#scanline]
	subs r0,r0,#159				;@ Return from emulation loop on this scanline
	movne r0,#1
	ldmfd sp!,{pc}

;@----------------------------------------------------------------------------
svSetInterruptStatus:		;@ r0 = interrupt status
;@----------------------------------------------------------------------------
	ldrb r2,[svvptr,#wsvIRQStatus]
	cmp r0,r2
	bxeq lr
	strb r0,[svvptr,#wsvIRQStatus]
svUpdateIrqEnable:
	ldrb r1,[svvptr,#wsvSystemControl]
	and r0,r0,r1,lsr#1
	ldr pc,[svvptr,#irqFunction]
;@----------------------------------------------------------------------------
svSetNMIStatus:		;@ r0 = NMI status, 0=off, 1=on
;@----------------------------------------------------------------------------
	ldrb r2,[svvptr,#wsvNMIStatus]
	cmp r0,r2
	bxeq lr
	strb r0,[svvptr,#wsvNMIStatus]
svUpdateNMIEnable:
	ldrb r1,[svvptr,#wsvSystemControl]
	and r0,r0,r1
	ldr pc,[svvptr,#nmiFunction]
;@----------------------------------------------------------------------------
copyScrollValues:			;@ r0 = destination
;@----------------------------------------------------------------------------
	mov r2,#(SCREEN_HEIGHT-GAME_HEIGHT)/2
	add r0,r0,r2,lsl#2			;@ 4 bytes per row
	mov r1,#0x100-(SCREEN_WIDTH-GAME_WIDTH)/2
	sub r1,r1,r2,lsl#16

	ldrb r2,[svvptr,#wsvXScroll]
	add r1,r1,r2
	ldrb r3,[svvptr,#wsvYScroll]
	cmp r3,#0xAB		;@ 170
	subpl r3,#0xAB
	addpl r1,r1,#0x40
	add r1,r1,r3,lsl#16

	mov r2,#GAME_HEIGHT
setScrlLoop:
	stmia r0!,{r1}
	add r3,r3,#1
	cmp r3,#0xAA		;@ 170
	subeq r1,r1,#0x00AA0000
	subs r2,r2,#1
	bne setScrlLoop

	bx lr

;@----------------------------------------------------------------------------
svConvertScreen:	;@ In r0 = dest
;@----------------------------------------------------------------------------
	stmfd sp!,{r3-r8,lr}

	ldr r1,[svvptr,#gfxRAM]	;@ Source
	ldr r4,=CHR_DECODE
	ldr lr,=0x1FE
	ldrb r8,[svvptr,#wsvXScroll]
	ldrb r2,[svvptr,#wsvYScroll]
	cmp r2,#0xAB		;@ 171
	addpl r8,r8,#0x40
	mov r8,r8,lsr#3
	add r1,r1,r8,lsl#1

	mov r7,#22				;@ 22 tiles high screen
scLoop:
	mov r6,#8				;@ 8 pix high tiles
tiLoop:
	mov r5,#21				;@ 21*8=168 pix
rwLoop:
	ldrh r3,[r1],#2			;@ Read 8 pixels
	ands r2,lr,r3,lsl#1
	ldrhne r2,[r4,r2]
	ands r3,lr,r3,lsr#7
	ldrhne r3,[r4,r3]
	orr r3,r2,r3,lsl#16
	and r8,r8,#0x1F
	str r3,[r0,r8,lsl#5]
	add r8,r8,#1
	subs r5,r5,#1
	bne rwLoop

	add r8,r8,#11
	add r1,r1,#6
	add r0,r0,#4
	subs r6,r6,#1
	bne tiLoop

	add r0,r0,#32*31
	subs r7,r7,#1
	bne scLoop

	ldmfd sp!,{r3-r8,pc}

;@----------------------------------------------------------------------------
#ifdef GBA
	.section .sbss				;@ For the GBA
#else
	.section .bss
#endif
	.align 2
CHR_DECODE:
	.space 0x200
SCROLL_BUFF:
	.space 160*4

#endif // #ifdef __arm__
