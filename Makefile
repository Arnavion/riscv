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
test: test-bww test-decompressor test-load test-ram_cache
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


.PHONY: test-bww
test-bww:
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
test-decompressor:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/rv_decompressor.sv" && ./test)


.PHONY: test-load
test-load:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/load32.sv" "$$src/tc/sv/load64.sv" && ./test)


.PHONY: test-ram_cache
test-ram_cache:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/ram_cache.sv" && ./test)


.PHONY: freestanding
freestanding:
	cd freestanding && cargo build --release --target riscv64-arnavion-none-elf.json -Z build-std=core


.PHONY: freestanding-inspect
freestanding-inspect: freestanding
	~/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-objdump -D ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding


EMULATOR_SAVE_DIR = ~/non-oss-root/steam/.local/share/godot/app_userdata/Turing\ Complete/schematics/architecture/RISC-V
EMULATOR_IN_FILE = ./tc/tower-of-alloy.S

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
