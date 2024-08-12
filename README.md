RISC-V assembler for an emulator I made in the game [Turing Complete](https://store.steampowered.com/app/1444480/Turing_Complete/) to learn about the ISA and have fun.

---

![Screenshot of the RISC-V emulator](https://www.arnavion.dev/img/tc-riscv.png)

[Video of the RISC-V emulator solving Towers of Alloy](https://www.arnavion.dev/img/tc-riscv-tower-of-alloy.mp4)

---

The assembler only supports what the emulator implements. Per the [unprivileged ISA spec version 20240411,](https://github.com/riscv/riscv-isa-manual/releases/tag/20240411) the emulator supports:

- RV32I 2.1 (32-bit integer register instructions)

Further extensions are not supported, notably instructions for hardware multiplication and division (M), hardware floats (F, D) and compressed instructions (C).

The assembler also only partially implements the full syntax supported by GNU / LLVM (enough to make the gas tests compile), and notably does not support labels, symbolic constants or data sections. It *does* support the register mnemonics like `ra` and pseudo-instructions like `j` listed in [the ASM manual](https://github.com/riscv-non-isa/riscv-asm-manual/blob/main/riscv-asm.md) (and older versions of the ISA spec before they were [removed](https://github.com/riscv/riscv-isa-manual/issues/1470)).

---

The `tc/` directory contains solutions for some of the game's architecture puzzles using the emulator.

The `*.S` files contain the assembler programs. Running `cargo run -- tc/foo.S` will print the compiled program to stdout which can then be copy-pasted into the game's Program component. The component must have "Data width" set to "32 Bit".

The `*.c` files contain equivalent C solutions that can be put in [Compiler Explorer](https://gcc.godbolt.org/) with compiler set to `RISC-V (32-bits) gcc` or `RISC-V rv32gc clang` and flags set to `--std=c23 -Os -march=rv32id`. Note that the assembler programs are hand-written and will not exactly match the compiler's output.

The emulator has the Level Input and Level Output wired up to memory address `2^32 - 1`, which is why the assembler programs refer to `-1(zero)` and the C programs refer to `IO = (volatile uint8_t*)(intptr_t)-1;`.

---

# License

AGPL-3.0-only

```
riscv

https://github.com/Arnavion/riscv

Copyright 2024 Arnav Singh

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, version 3 of the
License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
