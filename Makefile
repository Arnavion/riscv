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
		for compressed in 'false' 'true'; do \
			for f in tc/*.S; do cargo run -p as -- $$bitness "--compressed=$$compressed" "$$f" >/dev/null || exit 1; done; \
		done; \
	done
	cargo clippy --workspace --tests --examples
	cargo machete
