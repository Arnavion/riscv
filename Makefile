.PHONY: default
default:
	cargo build


.PHONY: clean
clean:
	rm -rf Cargo.lock target/


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
		for compress in 'false' 'true' 'Zcb'; do \
			for f in tc/*.S; do cargo run --bin riscv -- $$bitness "--compress=$$compress" "$$f" >/dev/null || exit 1; done; \
		done; \
	done
	cargo clippy --workspace --tests --examples
	cargo clippy --release --target freestanding/riscv64-arnavion-none-elf.json --bin freestanding -Z build-std=core
	cargo machete


.PHONY: freestanding
freestanding:
	cargo build --release --target freestanding/riscv64-arnavion-none-elf.json --bin freestanding -Z build-std=core


.PHONY: freestanding-inspect
freestanding-inspect: freestanding
	~/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-objdump -D ./target/riscv64-arnavion-none-elf/release/freestanding


EMULATOR_SAVE_DIR = ~/non-oss-root/steam/.local/share/godot/app_userdata/Turing\ Complete/schematics/architecture/RISC-V
EMULATOR_IN_FILE = ./tc/tower-of-alloy.S

.PHONY: freestanding-install
freestanding-install: freestanding
	cp ./target/riscv64-arnavion-none-elf/release/freestanding ~/non-oss-root/steam/program
	cp ./target/riscv64-arnavion-none-elf/release/freestanding $(EMULATOR_SAVE_DIR)/program
	cp $(EMULATOR_IN_FILE) ~/non-oss-root/steam/in_file
	cp $(EMULATOR_IN_FILE) $(EMULATOR_SAVE_DIR)/in_file
