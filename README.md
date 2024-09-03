RISC-V assembler for an emulator I made in the game [Turing Complete](https://store.steampowered.com/app/1444480/Turing_Complete/) to learn about the ISA and have fun.

---

![Screenshot of the RISC-V emulator](https://www.arnavion.dev/img/tc-riscv.png)

[Video of the RISC-V emulator solving Towers of Alloy](https://www.arnavion.dev/img/tc-riscv-tower-of-alloy.mp4)

---

Per the [unprivileged ISA spec version 20240411,](https://github.com/riscv/riscv-isa-manual/releases/tag/20240411) the assembler supports:

- RV32I 2.1 (32-bit integer register instructions)

- RV64I 2.1 (64-bit integer register instructions)

- Zca 1.0.0 (compressed instructions for integer registers)

- Zcb 1.0.0 (additional compressed instructions for integer registers)

- Zicntr 2.0 (cycle, time and instret CSRs)

- Zicsr 2.0 (CSR instructions)

Further extensions are not supported, notably instructions for hardware multiplication and division (M) and hardware floats (F, D).

Compressed instructions are supported in the sense that the assembler will encode regular instructions like `add` and `lbu` into the compressed form when compression is enabled. The mnemonics for the compressed instructions like `c.add` and `c.lbu` are not supported. Instructions that only exist in compressed instruction extensions like `c.lwsp` can be written as `lwsp` or `c.lwsp`.

The assembler also only partially implements the full syntax supported by GNU / LLVM, and notably does not support labels, symbolic constants or data sections. It *does* support the register mnemonics like `ra` and pseudo-instructions like `j` listed in [the ASM manual](https://github.com/riscv-non-isa/riscv-asm-manual/blob/ad0de8c004e29c9a7ac33cfd054f4d4f9392f2fb/src/asm-manual.adoc) (and older versions of the ISA spec before they were [removed](https://github.com/riscv/riscv-isa-manual/issues/1470)).

---

The `tc/solutions/` directory contains solutions for some of the game's architecture puzzles using the emulator.

The `*.S` files contain the assembler programs. Running `cargo run -p as -- tc/solutions/foo.S` will print the compiled program to stdout which can then be copy-pasted into the game's Program component. The component must have "Data width" set to "16 Bit". Running `cargo run -p as -- --compressed tc/solutions/foo.S` will do the same but enable compressed instructions. Running `cargo run -p as -- --compressed=Zcb tc/solutions/foo.S` will also enable compressed instructions from the Zcb extension.

The assembler does not consider whether the target architecture is 32-bit or 64-bit and will simply encode whatever instructions are given to it. This works fine because RV64I does not modify the behavior of RV32I instructions, except for a few situations:

1. The shift instructions take 5-bit shift amount in RV32I and 6-bit shift amount in RV64I.

2. The pseudo-instructions `sext.b`, `sext.h` and `zext.h` shift the source register by different amounts in RV32I vs RV64I.

3. `c.jal` is only valid in RV32C; an RV64C implementation would interpret it as `c.addiw` instead. Thus `jal` cannot be compressed into `c.jal` on RV64C.

Therefore the assembler also has a `--64` flag to explicitly set the target architecture to RV64I. When combined with the `--compressed` flag it will instruct the assembler to not compress `jal`.

The `*.c` files contain equivalent C solutions that can be put in [Compiler Explorer](https://gcc.godbolt.org/) with compiler set to `RISC-V (32-bits) gcc` or `RISC-V rv32gc clang` or corresponding 64-bit version, and flags set to `--std=c23 -Os -march=rv32id` or `--std=c23 -Os -march=rv64id`. Note that the assembler programs are hand-written and will not exactly match the compiler's output.

The emulator has the Level Input and Level Output wired up to memory address `2^xlen - 8`, which is why the assembler programs refer to `li fp, -8; lbu rd, 0(fp)` and the C programs refer to `IO = (volatile uint8_t*)(intptr_t)-8; x = *IO;`.

---

The `tc/sv/` directory contains SystemVerilog definitions, and the `tc/bsv/` directory contains BlueSpec SystemVerilog definitions, for various components related to the emulator.

The `tc/vis.sh` script in that directory can be used to generate an HTML file that renders Verilog, SystemVerilog and Bluespec SystemVerilog designs using [DigitalJS.](https://github.com/tilk/digitaljs)

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
