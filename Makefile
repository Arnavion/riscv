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
	for f in tc/*.S; do cargo run -p as -- "$$f" >/dev/null || exit 1; done
	cargo clippy --workspace --tests --examples
	cargo machete


.PHONY: test-load_store
test: test-load_store
test-load_store:
	src="$$PWD" && \
	d="$$(mktemp -d)" && \
	trap "rm -rf '$$d'" EXIT && \
	(cd "$$d" && iverilog -g2012 -DTESTING -o test "$$src/tc/sv/load_store.sv" && ./test)
