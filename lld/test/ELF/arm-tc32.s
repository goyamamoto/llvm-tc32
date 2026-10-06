# REQUIRES: arm
## Telink TC32 (-mcpu=tc32): objects whose Tag_CPU_name is "tc32" hold Thumb
## instructions in TC32's encoding. lld reads and patches them through Thumb's,
## fills gaps in code with the TC32 encoding of 0xd4d4, and refuses what a TC32
## image cannot hold: code in Thumb's encoding, thunks and PLT entries.

# RUN: rm -rf %t && split-file %s %t && cd %t
# RUN: llvm-mc -triple=thumbv4t-none-eabi -mcpu=tc32 -arm-add-build-attributes -filetype=obj a.s -o a.o
# RUN: llvm-mc -triple=thumbv4t-none-eabi -mcpu=tc32 -arm-add-build-attributes -filetype=obj b.s -o b.o
# RUN: ld.lld -T near.ld a.o b.o -o out
## The output keeps the first object's attributes, so llvm-objdump reads TC32.
# RUN: llvm-objdump -d out | FileCheck %s
# RUN: llvm-objdump -s -j .text out | FileCheck %s --check-prefix=BYTES

# CHECK-LABEL: <_start>:
# CHECK-NEXT:    0: 9000 9806     bl      0x10 <g>
# CHECK-NEXT:    4: c004          beq     0x10 <g>
# CHECK-NEXT:    6: 8003          b       0x10 <g>
# CHECK-NEXT:    8: 0800          ldr     r0, [pc, #0x0]
# CHECK-NEXT:    a: 6d00          pop     {pc}
# CHECK-NEXT:    c: 00 01 00 00   .word   0x00000100
# CHECK-LABEL: <g>:
# CHECK-NEXT:   10: 0770          bx      lr

## The gap after g, before the 16-byte aligned h: TC32's 0xc4d4.
# BYTES:      0000 00900698 04c00380 0008006d 00010000
# BYTES-NEXT: 0010 7007d4c4 d4c4d4c4 d4c4d4c4 d4c4d4c4
# BYTES-NEXT: 0020 7007

## TC32 code with code built for another core, in either order, or with code
## whose object names no core.
# RUN: llvm-mc -triple=thumbv4t-none-eabi -mcpu=arm7tdmi -arm-add-build-attributes -filetype=obj b.s -o thumb.o
# RUN: llvm-mc -triple=thumbv4t-none-eabi -filetype=obj b.s -o unnamed.o
# RUN: llvm-mc -triple=thumbv4t-none-eabi -filetype=obj data.s -o data.o
# RUN: not ld.lld -T near.ld a.o thumb.o -o /dev/null 2>&1 | FileCheck %s --check-prefix=MIX
# RUN: not ld.lld -T near.ld thumb.o a.o -o /dev/null 2>&1 | FileCheck %s --check-prefix=MIX
# RUN: not ld.lld -T near.ld a.o unnamed.o -o /dev/null 2>&1 | FileCheck %s --check-prefix=UNNAMED
# RUN: ld.lld -T near.ld a.o b.o data.o -o /dev/null
# MIX:     error: a.o: TC32 code cannot be linked with thumb.o, built for arm7tdmi
# UNNAMED: error: a.o: TC32 code cannot be linked with unnamed.o, which holds code and has no Tag_CPU_name

## A branch out of range would need a thunk.
# RUN: not ld.lld -T far.ld a.o b.o -o /dev/null 2>&1 | FileCheck %s --check-prefix=FAR
# FAR: error: a.o: TC32: the branch to g needs a thunk (out of range, or to ARM code), which a TC32 image cannot have

#--- a.s
	.syntax unified
	.section .text.a, "ax", %progbits
	.globl	_start
	.thumb_func
_start:
	bl	g		@ R_ARM_THM_CALL
	beq	g		@ R_ARM_THM_JUMP8
	b	g		@ R_ARM_THM_JUMP11
	ldr	r0, .Lp		@ resolved by the assembler
	pop	{pc}
	.p2align 2
.Lp:
	.word	0x100

#--- b.s
	.syntax unified
	.section .text.b, "ax", %progbits
	.globl	g
	.thumb_func
g:
	bx	lr
	.section .text.h, "ax", %progbits
	.p2align 4
	.globl	h
	.thumb_func
h:
	bx	lr

#--- data.s
	.data
	.word	1

#--- near.ld
SECTIONS {
  .text 0 : { *(.text.a) *(.text.b) *(.text.h) }
  .data : { *(.data) }
}

#--- far.ld
SECTIONS {
  .text.a 0 : { *(.text.a) }
  .text.b 0x1000000 : { *(.text.b) *(.text.h) }
  .data : { *(.data) }
}
