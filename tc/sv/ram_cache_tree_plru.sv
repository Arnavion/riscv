module ram_cache_tree_plru #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit clock,
	input bit reset,

	input bit ram_input_load,
	input bit ram_input_store,
	input bit ram_input_flush,

	input bit cache_left_address_in_cache,
	input logic cache_left_busy,
	input logic[xlen - 1:0] cache_left_load_value,

	input bit cache_right_address_in_cache,
	input logic cache_right_busy,
	input logic[xlen - 1:0] cache_right_load_value,

	output bit address_in_cache,

	output bit busy,

	output logic[xlen - 1:0] load_value,

	output bit cache_left_ram_input_load,
	output bit cache_left_ram_input_store,
	output bit cache_left_ram_input_flush,
	output bit cache_right_ram_input_load,
	output bit cache_right_ram_input_store,
	output bit cache_right_ram_input_flush
);
	bit oldest;
	wire next_oldest;

	ram_cache_tree_plru_inner #(.rv64(rv64)) ram_cache_tree_plru_inner_module (
		.ram_input_load(ram_input_load), .ram_input_store(ram_input_store), .ram_input_flush(ram_input_flush),
		.cache_left_address_in_cache(cache_left_address_in_cache), .cache_left_busy(cache_left_busy), .cache_left_load_value(cache_left_load_value),
		.cache_right_address_in_cache(cache_right_address_in_cache), .cache_right_busy(cache_right_busy), .cache_right_load_value(cache_right_load_value),
		.oldest(oldest),
		.address_in_cache(address_in_cache),
		.busy(busy),
		.load_value(load_value),
		.cache_left_ram_input_load(cache_left_ram_input_load), .cache_left_ram_input_store(cache_left_ram_input_store), .cache_left_ram_input_flush(cache_left_ram_input_flush),
		.cache_right_ram_input_load(cache_right_ram_input_load), .cache_right_ram_input_store(cache_right_ram_input_store), .cache_right_ram_input_flush(cache_right_ram_input_flush),
		.next_oldest(next_oldest)
	);

	always_ff @(posedge clock) begin
		if (reset)
			oldest <= '0;
		else
			oldest <= next_oldest;
	end
endmodule

module ram_cache_tree_plru_inner #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit ram_input_load,
	input bit ram_input_store,
	input bit ram_input_flush,

	input bit cache_left_address_in_cache,
	input logic cache_left_busy,
	input logic[xlen - 1:0] cache_left_load_value,

	input bit cache_right_address_in_cache,
	input logic cache_right_busy,
	input logic[xlen - 1:0] cache_right_load_value,

	input bit oldest,

	output bit address_in_cache,

	output bit busy,

	output logic[xlen - 1:0] load_value,

	output bit cache_left_ram_input_load,
	output bit cache_left_ram_input_store,
	output bit cache_left_ram_input_flush,

	output bit cache_right_ram_input_load,
	output bit cache_right_ram_input_store,
	output bit cache_right_ram_input_flush,

	output bit next_oldest
);
	assign address_in_cache = cache_left_address_in_cache | cache_right_address_in_cache;

	assign busy = cache_left_busy | cache_right_busy;

	assign load_value =
		cache_left_address_in_cache ? cache_left_load_value :
		cache_right_address_in_cache ? cache_right_load_value :
		'x;

	assign cache_left_ram_input_load = ram_input_load & (cache_left_address_in_cache | (~cache_right_address_in_cache & ~oldest));
	assign cache_left_ram_input_store = ram_input_store & (cache_left_address_in_cache | (~cache_right_address_in_cache & ~oldest));
	assign cache_left_ram_input_flush = ram_input_flush;

	assign cache_right_ram_input_load = ram_input_load & ~cache_left_address_in_cache & (cache_right_address_in_cache | oldest);
	assign cache_right_ram_input_store = ram_input_store & ~cache_left_address_in_cache & (cache_right_address_in_cache | oldest);
	assign cache_right_ram_input_flush = ram_input_flush & ~cache_left_busy;

	assign next_oldest =
		((~| {ram_input_load, ram_input_store}) | ram_input_flush) ?
			oldest :
			cache_left_address_in_cache | (~cache_right_address_in_cache & oldest);
endmodule

`ifdef TESTING
module test_ram_cache_tree_plru_inner;
	bit ram_input_load;
	bit ram_input_store;
	bit ram_input_flush;
	bit cache_left_address_in_cache;
	logic cache_left_busy;
	logic[31:0] cache_left_load_value;
	bit cache_right_address_in_cache;
	logic cache_right_busy;
	logic[31:0] cache_right_load_value;
	bit oldest;
	wire address_in_cache;
	wire busy;
	wire[31:0] load_value;
	wire cache_left_ram_input_load;
	wire cache_left_ram_input_store;
	wire cache_left_ram_input_flush;
	wire cache_right_ram_input_load;
	wire cache_right_ram_input_store;
	wire cache_right_ram_input_flush;
	wire next_oldest;
	ram_cache_tree_plru_inner #(.rv64(0)) ram_cache_tree_plru_inner_module (
		.ram_input_load(ram_input_load), .ram_input_store(ram_input_store), .ram_input_flush(ram_input_flush),
		.cache_left_address_in_cache(cache_left_address_in_cache), .cache_left_busy(cache_left_busy), .cache_left_load_value(cache_left_load_value),
		.cache_right_address_in_cache(cache_right_address_in_cache), .cache_right_busy(cache_right_busy), .cache_right_load_value(cache_right_load_value),
		.oldest(oldest),
		.address_in_cache(address_in_cache),
		.busy(busy),
		.load_value(load_value),
		.cache_left_ram_input_load(cache_left_ram_input_load), .cache_left_ram_input_store(cache_left_ram_input_store), .cache_left_ram_input_flush(cache_left_ram_input_flush),
		.cache_right_ram_input_load(cache_right_ram_input_load), .cache_right_ram_input_store(cache_right_ram_input_store), .cache_right_ram_input_flush(cache_right_ram_input_flush),
		.next_oldest(next_oldest)
	);

	task automatic test_case (
		input bit ram_input_load_,
		input bit ram_input_store_,
		input bit ram_input_flush_,
		input bit cache_left_address_in_cache_,
		input logic cache_left_busy_,
		input logic[31:0] cache_left_load_value_,
		input bit cache_right_address_in_cache_,
		input logic cache_right_busy_,
		input logic[31:0] cache_right_load_value_,
		input bit oldest_,
		input bit expected_address_in_cache,
		input bit expected_busy,
		input bit[31:0] expected_load_value,
		input bit expected_cache_left_ram_input_load,
		input bit expected_cache_left_ram_input_store,
		input bit expected_cache_left_ram_input_flush,
		input bit expected_cache_right_ram_input_load,
		input bit expected_cache_right_ram_input_store,
		input bit expected_cache_right_ram_input_flush,
		input bit expected_next_oldest
	);
		ram_input_load = ram_input_load_;
		ram_input_store = ram_input_store_;
		ram_input_flush = ram_input_flush_;
		cache_left_address_in_cache = cache_left_address_in_cache_;
		cache_left_busy = cache_left_busy_;
		cache_left_load_value = cache_left_load_value_;
		cache_right_address_in_cache = cache_right_address_in_cache_;
		cache_right_busy = cache_right_busy_;
		cache_right_load_value = cache_right_load_value_;
		oldest = oldest_;
		#1
		assert(address_in_cache == expected_address_in_cache) else $fatal(1, "address_in_cache: expected %h, got %h", expected_address_in_cache, address_in_cache);
		assert(busy == expected_busy) else $fatal(1, "busy: expected %h, got %h", expected_busy, busy);
		if (ram_input_load & ~busy) assert(load_value == expected_load_value) else $fatal(1, "load_value: expected %h, got %h", expected_load_value, load_value);
		assert(cache_left_ram_input_load == expected_cache_left_ram_input_load) else $fatal(1, "cache_left_ram_input_load: expected %h, got %h", expected_cache_left_ram_input_load, cache_left_ram_input_load);
		assert(cache_left_ram_input_store == expected_cache_left_ram_input_store) else $fatal(1, "cache_left_ram_input_store: expected %h, got %h", expected_cache_left_ram_input_store, cache_left_ram_input_store);
		assert(cache_left_ram_input_flush == expected_cache_left_ram_input_flush) else $fatal(1, "cache_left_ram_input_flush: expected %h, got %h", expected_cache_left_ram_input_flush, cache_left_ram_input_flush);
		assert(cache_right_ram_input_load == expected_cache_right_ram_input_load) else $fatal(1, "cache_right_ram_input_load: expected %h, got %h", expected_cache_right_ram_input_load, cache_right_ram_input_load);
		assert(cache_right_ram_input_store == expected_cache_right_ram_input_store) else $fatal(1, "cache_right_ram_input_store: expected %h, got %h", expected_cache_right_ram_input_store, cache_right_ram_input_store);
		assert(cache_right_ram_input_flush == expected_cache_right_ram_input_flush) else $fatal(1, "cache_right_ram_input_flush: expected %h, got %h", expected_cache_right_ram_input_flush, cache_right_ram_input_flush);
		assert(next_oldest == expected_next_oldest) else $fatal(1, "next_oldest: expected %h, got %h", expected_next_oldest, next_oldest);
	endtask

	initial begin
		test_case(
			'0, '0, '0,
			'0, '0, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'0,
			'0,
			'0,
			'x,
			'0, '0, '0,
			'0, '0, '0,
			'0
		);

		test_case(
			'1, '0, '0,
			'0, '1, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'0,
			'0,
			'1,
			'x,
			'1, '0, '0,
			'0, '0, '0,
			'0
		);

		test_case(
			'1, '0, '0,
			'0, '1, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'1,
			'0,
			'1,
			'x,
			'0, '0, '0,
			'1, '0, '0,
			'1
		);

		test_case(
			'1, '0, '0,
			'1, '0, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'0,
			'1,
			'0,
			32'h01234567,
			'1, '0, '0,
			'0, '0, '0,
			'1
		);

		test_case(
			'1, '0, '0,
			'1, '1, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'0,
			'1,
			'1,
			32'h01234567,
			'1, '0, '0,
			'0, '0, '0,
			'1
		);

		test_case(
			'1, '0, '0,
			'0, '0, 32'h01234567,
			'1, '0, 32'hfedcba98,
			'0,
			'1,
			'0,
			32'hfedcba98,
			'0, '0, '0,
			'1, '0, '0,
			'0
		);

		test_case(
			'1, '0, '0,
			'0, '0, 32'h01234567,
			'1, '1, 32'hfedcba98,
			'0,
			'1,
			'1,
			32'hfedcba98,
			'0, '0, '0,
			'1, '0, '0,
			'0
		);

		test_case(
			'0, '0, '1,
			'1, '0, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'0,
			'1,
			'0,
			32'hfedcba98,
			'0, '0, '1,
			'0, '0, '1,
			'0
		);

		test_case(
			'0, '0, '1,
			'1, '1, 32'h01234567,
			'0, '0, 32'hfedcba98,
			'0,
			'1,
			'1,
			32'hfedcba98,
			'0, '0, '1,
			'0, '0, '0,
			'0
		);

		test_case(
			'0, '0, '1,
			'1, '0, 32'h01234567,
			'0, '1, 32'hfedcba98,
			'0,
			'1,
			'1,
			32'hfedcba98,
			'0, '0, '1,
			'0, '0, '1,
			'0
		);
	end
endmodule
`endif
