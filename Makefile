.PHONY: default
default:
	cargo build


.PHONY: clean
clean:
	rm -rf Cargo.lock target/ freestanding/Cargo.lock freestanding/target/


.PHONY: outdated
outdated:
	cargo-outdated


.PHONY: print
print:
	git status --porcelain


.PHONY: test
test:
	cargo test --workspace
	for bitness in '--32' '--64'; do \
		for compressed in 'false' 'true' 'Zcb'; do \
			for zba in '' '--zba'; do \
				for zbb in '' '--zbb'; do \
					for f in tc/*.S; do cargo run -p as -- $$bitness "--compressed=$$compressed" $$zba $$zbb "$$f" >/dev/null || exit 1; done; \
				done; \
			done; \
		done; \
	done
	cargo clippy --workspace --tests --examples
	cd freestanding && cargo clippy --release --target riscv64-arnavion-none-elf.json -Z build-std=core
	cargo machete


.PHONY: test-booth_multiplier
test: test-booth_multiplier
test-booth_multiplier:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/booth_multiplier.sv" && ./test)


.PHONY: test-booth_multiplier_multi_cycle
test: test-booth_multiplier_multi_cycle
test-booth_multiplier_multi_cycle:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/booth_multiplier_multi_cycle.sv" && ./test)


.PHONY: test-bww-multiplier-generator
test: test-bww-multiplier-generator
test-bww-multiplier-generator:
	cargo run -p bww-multiplier-generator -- --mulh 8 >tc/sv/bww_multiplier.sv
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/bww_multiplier.sv" && ./test); \

	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	for fma in '' '--fma'; do \
		for mulh in '' '--mulh'; do \
			cargo run -p bww-multiplier-generator -- $$fma $$mulh 8 >"$$d/bww_multiplier.sv" && \
			(cd "$$d" && iverilog -g2012 -DTESTING -o test bww_multiplier.sv && ./test) || exit 1; \
		done; \
	done


.PHONY: test-decompressor
test: test-decompressor
test-decompressor:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/rv_decompressor.sv" && ./test)


.PHONY: test-decompressor_priority
test: test-decompressor_priority
test-decompressor_priority:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/rv_decompressor_priority.sv" && ./test)


.PHONY: test-load_store
test: test-load_store
test-load_store:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/load_store32.sv" "$$src/tc/sv/load_store64.sv" && ./test)


.PHONY: test-ram_cache
test: test-ram_cache
test-ram_cache:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/ram_cache.sv" && ./test)


.PHONY: test-ram_cache_tree_plru
test: test-ram_cache_tree_plru
test-ram_cache_tree_plru:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/ram_cache_tree_plru.sv" && ./test)


.PHONY: freestanding
freestanding:
	cd freestanding && cargo build --release --target riscv64-arnavion-none-elf.json -Z build-std=core


.PHONY: freestanding-inspect
freestanding-inspect: freestanding
	~/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-objdump -D ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding


EMULATOR_SAVE_DIR = ~/non-oss-root/steam/.local/share/godot/app_userdata/Turing\ Complete/schematics/architecture/RISC-V
EMULATOR_IN_FILE = ./tc/calibrating-laser-cannons-2.S

.PHONY: freestanding-install
freestanding-install: freestanding
	rm -f $(EMULATOR_SAVE_DIR)/sandbox/new_program.asm
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	objcopy ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding -O binary "$$d/flat" && \
	od --address-radix=none --format=x8 --output-duplicates --width=8 "$$d/flat" | \
		sed -Ee 's/^\s*0*(.*)/<U64>0x\1/;s/0x$$/0/' >>$(EMULATOR_SAVE_DIR)/sandbox/new_program.asm
	cp $(EMULATOR_IN_FILE) ~/non-oss-root/steam/in_file
	cp $(EMULATOR_IN_FILE) $(EMULATOR_SAVE_DIR)/in_file


.PHONY: simulator
test: simulator
simulator: freestanding
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	objcopy ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding -O binary "$$d/flat" && \
	cargo run --release -p simulator -- --mode in-order -- "$$d/flat" $(EMULATOR_IN_FILE)


.PHONY: simulator-ucode
test: simulator-ucode
simulator-ucode: freestanding
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	objcopy ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding -O binary "$$d/flat" && \
	cargo run --release -p simulator -- --mode in-order-ucode -- "$$d/flat" $(EMULATOR_IN_FILE)


.PHONY: simulator-ooo
test: simulator-ooo
simulator-ooo: freestanding
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	objcopy ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding -O binary "$$d/flat" && \
	cargo run --release -p simulator -- --mode out-of-order --ooo-max-retire-per-cycle 4 -- "$$d/flat" $(EMULATOR_IN_FILE)
