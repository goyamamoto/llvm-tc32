; Telink TC32 (-mcpu=tc32): Thumb-1 code generation for ARMv4T without ARM
; state, written in TC32's encoding. The object names its core in
; Tag_CPU_name, which tells the linker the encoding.
; RUN: llc -mtriple=thumbv4t-none-eabi -mcpu=tc32 %s -o - | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=thumbv4t-none-eabi -mcpu=tc32 -filetype=obj %s -o %t.o
; RUN: llvm-objdump -d -r --mcpu=tc32 %t.o | FileCheck %s --check-prefix=OBJ
; RUN: llvm-readelf -A %t.o | FileCheck %s --check-prefix=ATTR

; ASM:      .cpu tc32
; ASM:      f:
; ASM:      push {r7, lr}
; ASM-NEXT: bl g
; ASM-NEXT: adds r0, r0, #1
; ASM-NEXT: pop {r7, pc}

; OBJ:      <f>:
; OBJ-NEXT: 0: 6580 push {r7, lr}
; OBJ-NEXT: 2: 97ff 9ffe bl
; OBJ-NEXT: R_ARM_THM_CALL g
; OBJ-NEXT: 6: ec40 adds r0, r0, #0x1
; OBJ-NEXT: 8: 6d80 pop {r7, pc}

; ATTR:      TagName: CPU_name
; ATTR-NEXT: Value: tc32
; ATTR:      TagName: ARM_ISA_use
; ATTR-NEXT: Description: Not Permitted

declare i32 @g(i32)

define i32 @f(i32 %x) {
  %r = call i32 @g(i32 %x)
  %s = add i32 %r, 1
  ret i32 %s
}
