//===-- llvm/TargetParser/TC32.h - Telink TC32 instruction encoding -------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Telink's TC32 cores (TLSR825x, TLSR827x) execute the ARMv4T Thumb-1
// instruction set, without ARM state, with the top five bits of every 16-bit
// instruction assigned differently. The other eleven bits, and so every
// register, immediate and branch field, are those of Thumb. The ARM back end
// generates Thumb code as for any v4T core; with the TC32 feature the MC layer
// writes each instruction halfword in TC32's encoding, and lld and the
// disassembler go through Thumb to read and patch it.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_TARGETPARSER_TC32_H
#define LLVM_TARGETPARSER_TC32_H

#include <cstdint>

namespace llvm {
namespace TC32 {

/// The Thumb value of the top five bits of a halfword, indexed by its TC32
/// value.
inline constexpr uint8_t ThumbTop[32] = {
    0x08, 0x09, 0x0a, 0x0b, 0x10, 0x11, 0x12, 0x13, 0x0e, 0x0f, 0x0c,
    0x0d, 0x16, 0x17, 0x14, 0x15, 0x1c, 0x1d, 0x1e, 0x1f, 0x04, 0x05,
    0x06, 0x07, 0x1a, 0x1b, 0x18, 0x19, 0x02, 0x03, 0x00, 0x01};

/// The TC32 value of the top five bits of a halfword, indexed by its Thumb
/// value (the inverse of ThumbTop).
inline constexpr uint8_t TC32Top[32] = {
    0x1e, 0x1f, 0x1c, 0x1d, 0x14, 0x15, 0x16, 0x17, 0x00, 0x01, 0x02,
    0x03, 0x0a, 0x0b, 0x08, 0x09, 0x04, 0x05, 0x06, 0x07, 0x0e, 0x0f,
    0x0c, 0x0d, 0x1a, 0x1b, 0x18, 0x19, 0x10, 0x11, 0x12, 0x13};

/// The TC32 halfword with the same meaning as the Thumb halfword \p Thumb.
inline uint16_t toTC32(uint16_t Thumb) {
  return (uint16_t(TC32Top[Thumb >> 11]) << 11) | (Thumb & 0x7ff);
}

/// The Thumb halfword with the same meaning as the TC32 halfword \p TC32.
inline uint16_t toThumb(uint16_t TC32) {
  return (uint16_t(ThumbTop[TC32 >> 11]) << 11) | (TC32 & 0x7ff);
}

/// The TC32 halfword written for the Thumb instruction halfword \p Thumb.
/// Two Thumb instructions are written as others with the same effect where
/// it matters, in the forms Telink's own code uses:
/// - lsls rd, rm, #0 (movs rd, rm: the ARMv4T low register move, which
///   Thumb1InstrInfo::copyPhysReg emits only where CPSR is dead) as
///   adds rd, rm, #0. They differ in C and V only: lsls #0 keeps them, adds #0
///   clears them, so assembly code must not rely on movs keeping C or V;
/// - udf (the trap) as b . (a branch to itself): TC32 has no undefined
///   instruction known to trap.
inline uint16_t encodeInstr(uint16_t Thumb) {
  if ((Thumb & 0xffc0) == 0x0000)
    Thumb = 0x1c00 | (Thumb & 0x3f);
  else if ((Thumb & 0xff00) == 0xde00)
    Thumb = 0xe7fe;
  return toTC32(Thumb);
}

} // namespace TC32
} // namespace llvm

#endif // LLVM_TARGETPARSER_TC32_H
