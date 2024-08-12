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
	for f in tc/*.S; do cargo run -- "$$f" >/dev/null || exit 1; done
	cargo clippy --workspace --tests --examples
	cargo machete
