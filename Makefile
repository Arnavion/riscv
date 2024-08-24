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
	cargo machete


.PHONY: test-as
test: test-as
test-as:
	for bitness in '--32' '--64'; do \
		for compressed in 'false' 'true'; do \
			for f in tc/solutions/*.S; do cargo run -p as -- $$bitness "--compressed=$$compressed" "$$f" >/dev/null || exit 1; done; \
		done; \
	done


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
