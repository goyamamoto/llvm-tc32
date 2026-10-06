@ Telink TC32 (-mcpu=tc32): Thumb-1 instructions written in TC32's encoding
@ (llvm/TargetParser/TC32.h): the top five bits of each halfword permuted,
@ the other eleven bits as in Thumb. Fixups resolved by the assembler and
@ those left to the linker go through Thumb's encoding; data stays as it is.
@ RUN: llvm-mc -triple=thumbv4t-none-eabi -mcpu=tc32 -filetype=obj %s -o %t.o
@ RUN: llvm-objdump -s -j .text %t.o | FileCheck %s --check-prefix=TC32
@ RUN: llvm-objdump -d --mcpu=tc32 %t.o | FileCheck %s --check-prefix=DIS
@ RUN: llvm-readelf -r %t.o | FileCheck %s --check-prefix=REL
@ With build attributes (as clang writes them) the object names its CPU, and
@ llvm-objdump takes the TC32 encoding from that:
@ RUN: llvm-mc -triple=thumbv4t-none-eabi -mcpu=tc32 -arm-add-build-attributes -filetype=obj %s -o %t.attr.o
@ RUN: llvm-readelf -A %t.attr.o | FileCheck %s --check-prefix=ATTR
@ RUN: llvm-objdump -d %t.attr.o | FileCheck %s --check-prefix=DIS
@ The same source for arm7tdmi, in Thumb's encoding:
@ RUN: llvm-mc -triple=thumbv4t-none-eabi -mcpu=arm7tdmi -filetype=obj %s -o %t.thumb.o
@ RUN: llvm-objdump -s -j .text %t.thumb.o | FileCheck %s --check-prefix=THUMB

	.syntax unified
	.text
	.globl	f
	.type	f, %function
	.thumb_func
f:
	adds	r0, r1, #1		@ 1c48 -> ec48
	movs	r1, r2			@ lsls r1, r2, #0 (0011) as adds r1, r2, #0 (1c11) -> ec11
	ldr	r3, .Lpool		@ 4b04 -> 0b04: the offset filled in by the assembler
	beq	1f			@ d002 -> c002
	bl	g			@ f7ff fffe -> 97ff 9ffe: R_ARM_THM_CALL, addend -4 in the fields
	b	f			@ e7fe -> 87fe: R_ARM_THM_JUMP11 (f is global)
1:	pop	{r4, pc}		@ bd10 -> 6d10
	udf	#0			@ de00 as b . (e7fe) -> 87fe
	.inst.n	0xbbc0			@ the Thumb value standing for tmcsr r0 -> 6bc0
	.p2align 3			@ padding mov r8, r8: 46c0 -> 06c0
.Lpool:
	.word	0x12345678		@ data: unchanged

@ TC32:      0000 48ec11ec 040b02c0 ff97fe9f fe87106d
@ TC32-NEXT: 0010 fe87c06b c006c006 78563412

@ THUMB:      0000 481c1100 044b02d0 fff7feff fee710bd
@ THUMB-NEXT: 0010 00dec0bb c046c046 78563412

@ DIS:      0: ec48         	adds	r0, r1, #0x1
@ DIS-NEXT: 2: ec11         	adds	r1, r2, #0x0
@ DIS-NEXT: 4: 0b04         	ldr	r3, [pc, #0x10]
@ DIS-NEXT: 6: c002         	beq	0xe
@ DIS-NEXT: 8: 97ff 9ffe    	bl	0x8
@ DIS-NEXT: c: 87fe         	b	0xc
@ DIS-NEXT: e: 6d10         	pop	{r4, pc}
@ DIS-NEXT: 10: 87fe        	b	0x10
@ DIS-NEXT: 12: 6bc0        	<unknown>
@ DIS-NEXT: 14: 06c0        	mov	r8, r8
@ DIS-NEXT: 16: 06c0        	mov	r8, r8
@ DIS-NEXT: 18: 78 56 34 12 	.word	0x12345678

@ ATTR:      TagName: CPU_name
@ ATTR-NEXT: Value: tc32

@ REL: 00000008 {{.*}} R_ARM_THM_CALL {{.*}} g
@ REL: 0000000c {{.*}} R_ARM_THM_JUMP11 {{.*}} f
