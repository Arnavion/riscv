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
				for f in tc/*.S; do cargo run -p as -- $$bitness "--compressed=$$compressed" $$zba "$$f" >/dev/null || exit 1; done; \
			done; \
		done; \
	done
	cargo clippy --workspace --tests --examples
	cd freestanding && cargo clippy --release --target riscv64-arnavion-none-elf.json -Z build-std=core
	cargo machete


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


.PHONY: test-load
test: test-load
test-load:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/load32.sv" "$$src/tc/sv/load64.sv" && ./test)


.PHONY: test-ram_cache
test: test-ram_cache
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
	cp ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding ~/non-oss-root/steam/program
	cp ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding $(EMULATOR_SAVE_DIR)/program
	cp $(EMULATOR_IN_FILE) ~/non-oss-root/steam/in_file
	cp $(EMULATOR_IN_FILE) $(EMULATOR_SAVE_DIR)/in_file
