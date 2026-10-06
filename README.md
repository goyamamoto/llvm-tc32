# llvm-tc32

LLVM 23.1.2 for Telink's TC32 cores (TLSR825x, TLSR827x): with `-mcpu=tc32`,
clang and lld build TC32 code and link TC32 images directly.

TC32 executes ARMv4T Thumb-1 without ARM state. Each 16-bit TC32 instruction
is the Thumb halfword with the same meaning, its top five bits assigned
differently; the other eleven bits, and so every register, immediate and
branch field, are Thumb's. LLVM's Thumb-1 code generation therefore serves
TC32 as it is. This branch adds what TC32 needs beyond that: returns that do
not depend on ARM state, and the TC32 encoding in the assembler, the linker
and the disassembler.

| | |
|---|---|
| Base | `llvmorg-23.1.2`, the LLVM release TC32 firmware and [tc32-devtools](https://github.com/goyamamoto/tc32-devtools)' checks are built with; a newer release becomes the base once those checks have been taken again with it |
| Branch | `tc32/23.1.2`: the release tag, the three changes below and this README |
| Licence | Apache-2.0 WITH LLVM-exception, LLVM's licence (`LICENSE.TXT`) |

## Changes

One commit each, on top of the tag:

1. **[ARM] Thumb-1: return with POP {..., pc} on a v4T core without ARM
   state.** On ARMv4T a `pop` into `pc` does not interwork, so before v5T
   LLVM returns from a Thumb-1 function by popping the saved `lr` into a low
   register and `bx` to it. A core without ARM state (LLVM's feature
   `noarm`) has only Thumb callers; there a v4T core now returns as v5T
   does, with `pop {..., pc}`. Telink's own code returns this way: tc32-devtools'
   `compiler/vendor_forms.txt` counts `pop pc` at 1,341 sites in Telink's
   libraries and 1,968 in programs built by Telink's compiler. Without
   `noarm`, code for v4T is unchanged.
2. **[ARM] TC32: -mcpu=tc32 writes Thumb-1 code in Telink TC32's encoding.**
   The CPU `tc32` is ARMv4T with `noarm` and a feature `tc32` that only the
   MC layer reads, so the code generated is that of a Thumb-only v4T core:
   - the encoding: `llvm/include/llvm/TargetParser/TC32.h`;
   - the code emitter, the assembler's fixups (filled in through Thumb's
     encoding), alignment padding and `.inst`;
   - the disassembler;
   - `Tag_CPU_name` "tc32" in the objects' build attributes, from which
     `llvm-objdump` reads TC32 code without `--mcpu`.
3. **[lld][ELF] TC32: link objects whose Tag_CPU_name is tc32.** Relocations
   patch TC32 instructions through Thumb's encoding, and gaps in code are
   filled with TC32's form of the trap fill. A branch that would need a
   thunk, a PLT entry, and an object built for another core or holding code
   without naming its core are errors: lld would write Thumb or ARM code for
   the first two, and nothing tells which encoding the code of the last is in.

Two Thumb instructions are written as others, in the forms Telink's own code
uses: `lsls rd, rm, #0` (`movs rd, rm`, LLVM's ARMv4T low register move,
which it emits only where the flags are dead) as `adds rd, rm, #0`, and
`udf` as `b .`. The first pair differs in C and V only, so assembly code must
not rely on `movs rd, rm` keeping them.

## Build

```
cmake -G Ninja -S llvm -B build -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_PROJECTS="clang;lld" -DLLVM_TARGETS_TO_BUILD=ARM
ninja -C build clang lld llvm-objcopy llvm-objdump llvm-readelf llvm-nm llvm-ar llvm-size
```

The results below were measured with this configuration (Release, without
assertions, the ARM target only).

## Use

```
clang --target=thumbv4t-none-eabi -mcpu=tc32 -mthumb -mfloat-abi=soft -c main.c
clang --target=thumbv4t-none-eabi -mcpu=tc32 -mthumb -c start.S
ld.lld -T link.ld start.o main.o -o fw.elf
llvm-objcopy -O binary --gap-fill=0xff fw.elf fw.bin
llvm-objdump -d fw.elf
```

- `-mthumb` is needed. Without it clang builds ARM code, which `tc32`
  refuses ("Function 'f' uses ARM instructions, but the target does not
  support ARM mode execution").
- TC32 has no divide instruction: the division and other `__aeabi_*`
  helpers are in tc32-devtools' `compiler/runtime`.
- clang writes the build attributes for C and for assembly. `llvm-mc`
  writes them only with `-arm-add-build-attributes`; without them lld does
  not know an object as TC32.
- `.inst` values are written in the encoding of the CPU the assembler was
  started with: do not switch to or from `tc32` with `.cpu` inside a file.
- LTO: clang passes `-mcpu=tc32` to the link (`-plugin-opt=mcpu=tc32`),
  which the LTO output's build attributes need. LTO with `-mcpu=tc32` has
  not been tested.
- The same code in Thumb's encoding comes from `-mcpu=arm7tdmi -mthumb
  -Xclang -target-feature -Xclang +noarm`; tc32-devtools' `thumb2tc32`
  then re-encodes the linked image as TC32. The two ways give the same
  image (below).

## Verification

Measured on macOS (arm64 host) with this branch built as above and
tc32-devtools' checks: the semantics test `checks/sem` (helpers built for
both divider settings) and Csmith programs as `checks/ccdiff` builds them
(levels O0, O2, Os, Oz and ZMK's flags). For change 1 the programs run in
tc32-devtools' emulator against the host; for `-mcpu=tc32` their images are
compared with those of the Thumb build.

| Check | Result |
|---|---|
| lit: the three changes' tests; `llvm/test/CodeGen/{ARM,Thumb,Thumb2}`, `MC/ARM`, `MC/Disassembler/ARM`, the ARM tests of `llvm-objdump` and `llvm-readobj`, `Object`; `lld/test/ELF`; clang's ARM driver, preprocessor and code generation tests and its ARM CPU list | 5,742 tests: 3,820 passed, 1,915 unsupported (other targets), 7 expectedly failed, 0 failed |
| unit tests | `TargetParserTests` 670 passed, 3 skipped; `ObjectTests` 150 passed; the attribute parser tests of `SupportTests` 18 passed |
| change 1, sem with `noarm` | every result equal to the host's (64 per image, O0, O2, Os, Oz, both divider settings, the emulator's Python and Go engines); no instruction form Telink's code never uses |
| change 1, sem without `noarm` | all 8 images identical to unpatched LLVM 23.1.2's, image and disassembly |
| change 1, Csmith with `noarm`, seeds 1-1000 (889 programs run on the host) | 4,444 builds run with the host's result, 0 different; 1 over the emulator's instruction limit (seed 773 at O0, also without the change) |
| change 1, instruction forms of those Csmith images | 6 of 4,445 images have a conditional branch on V clear (`bvc`), a form Telink's code never uses; unpatched LLVM 23.1.2 emits it in the same 6 builds |
| `-mcpu=tc32` against `noarm` Thumb code re-encoded by `thumb2tc32`: sem (8 images) and Csmith seeds 1-1000 (five levels) | 8/8 and 5,000/5,000 images identical |
| ZMK firmware for three TLSR8278 keyboards | with `noarm`, 5,016-5,448 B (4.2 %) smaller than without; `-mcpu=tc32` images identical to the `noarm` + `thumb2tc32` images |

Change 1 was measured with change 1 alone. Changes 2 and 3 leave code
generation as it is: with them, the `noarm` firmware images are identical to
those built with change 1 alone. The `-mcpu=tc32` images are laid out as
`thumb2tc32` lays out images (each loadable segment's bytes at its physical
address, `0xff` between segments); `llvm-objcopy -O binary` writes the same
code but fills gaps between sections in one segment differently.

Firmware built with this branch has not run on hardware yet.

---

# The LLVM Compiler Infrastructure

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/llvm/llvm-project/badge)](https://securityscorecards.dev/viewer/?uri=github.com/llvm/llvm-project)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/8273/badge)](https://www.bestpractices.dev/projects/8273)
[![libc++](https://github.com/llvm/llvm-project/actions/workflows/libcxx-build-and-test.yaml/badge.svg?branch=main&event=schedule)](https://github.com/llvm/llvm-project/actions/workflows/libcxx-build-and-test.yaml?query=event%3Aschedule)

Welcome to the LLVM project!

This repository contains the source code for LLVM, a toolkit for the
construction of highly optimized compilers, optimizers, and run-time
environments.

The LLVM project has multiple components. The core of the project is
itself called "LLVM". This contains all of the tools, libraries, and header
files needed to process intermediate representations and convert them into
object files. Tools include an assembler, disassembler, bitcode analyzer, and
bitcode optimizer.

C-like languages use the [Clang](https://clang.llvm.org/) frontend. This
component compiles C, C++, Objective-C, and Objective-C++ code into LLVM bitcode
-- and from there into object files, using LLVM.

Other components include:
the [libc++ C++ standard library](https://libcxx.llvm.org),
the [LLD linker](https://lld.llvm.org), and more.

## Getting the Source Code and Building LLVM

Consult the
[Getting Started with LLVM](https://llvm.org/docs/GettingStarted.html#getting-the-source-code-and-building-llvm)
page for information on building and running LLVM.

For information on how to contribute to the LLVM project, please take a look at
the [Contributing to LLVM](https://llvm.org/docs/Contributing.html) guide.

## Getting in touch

Join the [LLVM Discourse forums](https://discourse.llvm.org/), [Discord
chat](https://discord.gg/xS7Z362),
[LLVM Office Hours](https://llvm.org/docs/GettingInvolved.html#office-hours) or
[Regular sync-ups](https://llvm.org/docs/GettingInvolved.html#online-sync-ups).

The LLVM project has adopted a [code of conduct](https://llvm.org/docs/CodeOfConduct.html) for
participants to all modes of communication within the project.
