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


# BSV has no equivalent of `$fatal`, so test binaries exit with 0 even on failure.
# Workaround is to `$display` a message on test pass and grep the output for it.
#
# Ref: https://github.com/B-Lang-org/bsc/issues/296
define test-bsv =
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	mkdir -p "$$d/b" && \
	bsc \
		-aggressive-conditions \
		-bdir "$$d/b" \
		-O \
		-opt-undetermined-vals \
		-p "+:$$src/tc/bsv" \
		-promote-warnings G0010:G0023 \
		-sim \
		-suppress-warnings P0102 \
		-u \
		-D TESTING=1 \
		"$$src/$<" && \
	bsc \
		-aggressive-conditions \
		-e mkTest \
		-O \
		-o "$$d/test" \
		-opt-undetermined-vals \
		-p "+:$$src/tc/bsv" \
		-promote-warnings G0010:G0023 \
		-sim \
		-simdir "$$d" \
		-suppress-warnings P0102 \
		-u \
		-D TESTING=1 \
		"$$d/b/"*.ba && \
	output="$$("$$d/test" | tee /dev/stderr)" && \
	grep -q 'Test passed' <<< "$$output"
endef


define test-sv =
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/$<" && ./test)
endef


.PHONY: test-lint
test: test-lint
test-lint:
	cargo test --workspace
	cargo clippy --workspace --tests --examples
	cd freestanding && cargo clippy --release --target riscv64-arnavion-none-elf.json -Z build-std=core
	cargo machete


.PHONY: test-as
test: test-as
test-as:
	for bitness in '--32' '--64'; do \
		for compressed in 'false' 'true' 'Zcb'; do \
			for zba in '' '--zba'; do \
				for zbb in '' '--zbb'; do \
					for f in tc/solutions/*.S; do cargo run -p as -- $$bitness "--compressed=$$compressed" $$zba $$zbb "$$f" >/dev/null || exit 1; done; \
				done; \
			done; \
		done; \
	done


.PHONY: test-booth_multiplier-sv
test: test-booth_multiplier-sv
test-booth_multiplier-sv: tc/sv/booth_multiplier.sv
	$(test-sv)


.PHONY: test-booth_multiplier-bsv
test: test-booth_multiplier-bsv
test-booth_multiplier-bsv: tc/bsv/BoothMultiplier.bsv
	$(test-bsv)


.PHONY: test-booth_multiplier_multi_cycle-sv
test: test-booth_multiplier_multi_cycle-sv
test-booth_multiplier_multi_cycle-sv: tc/sv/booth_multiplier_multi_cycle.sv
	$(test-sv)


.PHONY: test-booth_multiplier_multi_cycle-bsv
test: test-booth_multiplier_multi_cycle-bsv
test-booth_multiplier_multi_cycle-bsv: tc/bsv/BoothMultiplierMultiCycle.bsv
	$(test-bsv)


.PHONY: test-decompressor-sv
test: test-decompressor-sv
test-decompressor-sv: tc/sv/rv_decompressor.sv
	$(test-sv)


.PHONY: test-decompressor-bsv
test: test-decompressor-bsv
test-decompressor-bsv: tc/bsv/RvDecompressor.bsv
	$(test-bsv)


.PHONY: test-decompressor_priority-sv
test: test-decompressor_priority-sv
test-decompressor_priority-sv: tc/sv/rv_decompressor_priority.sv
	$(test-sv)


.PHONY: test-decompressor_priority-bsv
test: test-decompressor_priority-bsv
test-decompressor_priority-bsv: tc/bsv/RvDecompressorPriority.bsv
	$(test-bsv)


.PHONY: test-load_store32
test: test-load_store32
test-load_store32: tc/sv/load_store32.sv
	$(test-sv)


.PHONY: test-load_store64
test: test-load_store64
test-load_store64: tc/sv/load_store64.sv
	$(test-sv)


.PHONY: test-ram_cache
test: test-ram_cache
test-ram_cache: tc/sv/ram_cache.sv
	$(test-sv)


.PHONY: freestanding
freestanding:
	cd freestanding && cargo build --release --target riscv64-arnavion-none-elf.json -Z build-std=core


.PHONY: freestanding-inspect
freestanding-inspect: freestanding
	~/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-objdump -D ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding


EMULATOR_SAVE_DIR = ~/non-oss-root/steam/.local/share/godot/app_userdata/Turing\ Complete/schematics/architecture/RISC-V
EMULATOR_IN_FILE = ./tc/solutions/tower-of-alloy.S

.PHONY: freestanding-install
freestanding-install: freestanding
	cp ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding ~/non-oss-root/steam/program
	cp ./freestanding/target/riscv64-arnavion-none-elf/release/freestanding $(EMULATOR_SAVE_DIR)/program
	cp $(EMULATOR_IN_FILE) ~/non-oss-root/steam/in_file
	cp $(EMULATOR_IN_FILE) $(EMULATOR_SAVE_DIR)/in_file
