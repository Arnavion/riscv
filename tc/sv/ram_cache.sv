/*

+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Current | Load | Store | Flush |     Address     | Slow | -> |  Next   |  Next Address   | Busy |   Load Value    | Fast  |      Fast       | Slow | Slow  |      Slow       |
|  State  |      |       |       |                 | Busy | -> |  State  |                 |      |                 | Store |   Store Value   | Load | Store |     Address     |
+=========+======+=======+=======+=================+======+====+=========+=================+======+=================+=======+=================+======+=======+=================+
| Clean   | 0    | 0     |       |                 |      | -> | Clean   | Current Address | 0    |                 | 0     |                 | 0    | 0     |                 |
| Clean   | 1    | 0     | 0     | Current Address |      | -> | Clean   | Current Address | 0    | Fast Load Value | 0     |                 | 0    | 0     |                 |
| Clean   | 1    | 0     | 0     | New Address     |      | -> | Reading | New Address     | 1    |                 | 0     |                 | 1    | 0     | New Address     |
| Clean   | 0    | 1     | 0     | Current Address |      | -> | Dirty   | Current Address | 0    | Fast Load Value | 1     | Store Value     | 0    | 0     |                 |
| Clean   | 0    | 1     | 0     | New Address     |      | -> | Reading | New Address     | 1    |                 | 0     |                 | 1    | 0     | New Address     |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Dirty   | 0    | 0     | 0     |                 |      | -> | Dirty   | Current Address | 0    |                 | 0     |                 | 0    | 0     |                 |
| Dirty   | 1    | 0     | 0     | Current Address |      | -> | Dirty   | Current Address | 0    | Fast Load Value | 0     |                 | 0    | 0     |                 |
| Dirty   | 1    | 0     | 0     | New Address     |      | -> | Writing | New Address     | 1    |                 | 0     |                 | 0    | 1     | Current Address |
| Dirty   | 0    | 1     | 0     | Current Address |      | -> | Dirty   | Current Address | 0    | Fast Load Value | 1     | Store Value     | 0    | 0     |                 |
| Dirty   | 0    | 1     | 0     | New Address     |      | -> | Writing | New Address     | 1    |                 | 0     |                 | 0    | 1     | Current Address |
| Dirty   | 0    | 0     | 1     |                 |      | -> | Writing | Current Address | 1    |                 | 0     |                 | 0    | 1     | Current Address |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Writing |      |       |       |                 | 1    | -> | Writing | Current Address | 1    |                 | 0     |                 | 0    | 0     |                 |
| Writing | 1    | 0     | 0     |                 | 0    | -> | Reading | Current Address | 1    |                 | 0     |                 | 1    | 0     | Current Address |
| Writing | 0    | 1     | 0     |                 | 0    | -> | Reading | Current Address | 1    |                 | 0     |                 | 1    | 0     | Current Address |
| Writing | 0    | 0     | 1     |                 | 0    | -> | Reading | Current Address | 1    |                 | 0     |                 | 0    | 0     |                 |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Reading |      |       |       |                 | 1    | -> | Reading | Current Address | 1    |                 | 0     |                 | 0    | 0     |                 |
| Reading |      |       |       |                 | 0    | -> | Clean   | Current Address | 1    |                 | 1     | Slow Load Value | 0    | 0     |                 |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+

 */

typedef enum bit[2:0] {
	RamInput_None = 3'b000,
	RamInput_Load = 3'b001,
	RamInput_Store = 3'b010,
	RamInput_Flush = 3'b100
} RamInput;


// [ram_block_address|isa_block_address|isa_byte_address]
// [                       address                      ]
module ram_cache #(
	parameter rv64 = 1,

	// Number of bits in a RAM block, ie a block that the RAM loads and stores in one shot.
	parameter ram_block_width = 512,

	// Number of bits in an ISA address.
	//
	// Also, the number of bits in an ISA block, ie a block that the ISA addresses in one instruction.
	localparam xlen = rv64 ? 64 : 32,

	// Number of bits needed to address a RAM block.
	localparam ram_block_address_width = xlen - $clog2(ram_block_width / 8),

	// Number of bits needed to address a byte within an ISA block.
	localparam isa_byte_address = $clog2(xlen / 8),

	// Number of bits needed to address an ISA block within a RAM block.
	localparam isa_block_address_width = $clog2(ram_block_width / xlen) // xlen - ram_block_address_width - isa_byte_address
) (
	input bit clock,
	input bit reset,

	input logic[xlen - 1:isa_byte_address] address,
	input RamInput ram_input,
	input logic[xlen - 1:0] store_value,

	input logic[ram_block_width - 1:0] fast_load_value,

	input bit slow_busy,
	input logic[ram_block_width - 1:0] slow_load_value,

	output bit[ram_block_address_width - 1:0] inspect_cached_ram_block_address,
	output bit inspect_state_is_dirty,
	output bit inspect_state_is_writing,
	output bit inspect_state_is_reading,

	output bit busy,

	output logic[xlen - 1:0] load_value,

	output bit fast_store,
	output logic[ram_block_width - 1:0] fast_store_value,

	output bit slow_load,
	output bit slow_store,
	output logic[ram_block_address_width - 1:0] slow_address
);
	typedef enum bit[1:0] {
		State_Clean = 2'b00,
		State_Dirty = 2'b01,
		State_Writing = 2'b11,
		State_Reading = 2'b10
	} State;

	State state;
	bit[ram_block_address_width - 1:0] cached_ram_block_address;

	State next_state;
	bit[ram_block_address_width - 1:0] next_cached_ram_block_address;

	assign inspect_cached_ram_block_address = cached_ram_block_address;
	assign inspect_state_is_dirty = state == State_Dirty;
	assign inspect_state_is_writing = state == State_Writing;
	assign inspect_state_is_reading = state == State_Reading;

	wire[isa_block_address_width - 1:0] isa_block_address = address[isa_byte_address+:isa_block_address_width];
	wire[ram_block_address_width - 1:0] ram_block_address = address[isa_byte_address + isa_block_address_width+:ram_block_address_width];

	always_ff @(posedge clock) begin
		if (reset) begin
			state <= State_Clean;
			cached_ram_block_address <= '0;
		end else begin
			state <= next_state;
			cached_ram_block_address <= next_cached_ram_block_address;
		end
	end

	always_comb begin
		next_state = state;
		next_cached_ram_block_address = cached_ram_block_address;

		busy = '0;
		load_value = 'x;
		fast_store = '0;
		fast_store_value = 'x;
		slow_load = '0;
		slow_store = '0;
		slow_address = 'x;

		unique case (state)
			State_Clean: unique case (ram_input)
				RamInput_None, RamInput_Flush: ;

				RamInput_Load: if (ram_block_address == cached_ram_block_address) begin
					load_value = fast_load_value[{isa_block_address, $clog2(xlen)'('0)}+:xlen];
				end else begin
					next_state = State_Reading;
					next_cached_ram_block_address = ram_block_address;
					busy = '1;
					slow_load = '1;
					slow_address = ram_block_address;
				end

				RamInput_Store: if (ram_block_address == cached_ram_block_address) begin
					next_state = State_Dirty;
					load_value = fast_load_value[{isa_block_address, $clog2(xlen)'('0)}+:xlen];
					fast_store = '1;
					fast_store_value = fast_load_value;
					fast_store_value[{isa_block_address, $clog2(xlen)'('0)}+:xlen] = store_value;
				end else begin
					next_state = State_Reading;
					next_cached_ram_block_address = ram_block_address;
					busy = '1;
					slow_load = '1;
					slow_address = ram_block_address;
				end
			endcase

			State_Dirty: unique case (ram_input)
				RamInput_None: ;

				RamInput_Load: if (ram_block_address == cached_ram_block_address) begin
					load_value = fast_load_value[{isa_block_address, $clog2(xlen)'('0)}+:xlen];
				end else begin
					next_state = State_Writing;
					next_cached_ram_block_address = ram_block_address;
					busy = '1;
					slow_store = '1;
					slow_address = cached_ram_block_address;
				end

				RamInput_Store: if (ram_block_address == cached_ram_block_address) begin
					load_value = fast_load_value[{isa_block_address, $clog2(xlen)'('0)}+:xlen];
					fast_store = '1;
					fast_store_value = fast_load_value;
					fast_store_value[{isa_block_address, $clog2(xlen)'('0)}+:xlen] = store_value;
				end else begin
					next_state = State_Writing;
					next_cached_ram_block_address = ram_block_address;
					busy = '1;
					slow_store = '1;
					slow_address = cached_ram_block_address;
				end

				RamInput_Flush: begin
					next_state = State_Writing;
					busy = '1;
					slow_store = '1;
					slow_address = cached_ram_block_address;
				end
			endcase

			State_Writing: if (slow_busy) begin
				busy = '1;
			end else begin
				next_state = State_Reading;
				busy = '1;
				slow_load = '1;
				slow_address = cached_ram_block_address;
			end

			State_Reading: if (slow_busy) begin
				busy = '1;
			end else begin
				next_state = State_Clean;
				busy = '1;
				fast_store = '1;
				fast_store_value = slow_load_value;
			end
		endcase
	end
endmodule

`ifdef TESTING
module test_ram_cache #(
	localparam rv64 = 1,

	// Number of bits in a RAM block, ie a block that the RAM loads and stores in one shot.
	localparam ram_block_width = rv64 ? 128 : 64,

	// Number of bits in an ISA address.
	//
	// Also, the number of bits in an ISA block, ie a block that the ISA addresses in one instruction.
	localparam xlen = rv64 ? 64 : 32,

	// Number of bits needed to address a RAM block.
	localparam ram_block_address_width = xlen - $clog2(ram_block_width / 8),

	// Number of bits needed to address a byte within an ISA block.
	localparam isa_byte_address = $clog2(xlen / 8),

	// Number of bits needed to address an ISA block within a RAM block.
	localparam isa_block_address_width = $clog2(ram_block_width / xlen) // xlen - ram_block_address_width - isa_byte_address
);
	bit clock;
	bit reset;

	logic[xlen - 1:isa_byte_address] address;
	RamInput ram_input;
	logic[xlen - 1:0] store_value;

	logic[ram_block_width - 1:0] fast_load_value;

	bit slow_busy;
	logic[ram_block_width - 1:0] slow_load_value;

	wire[ram_block_address_width - 1:0] inspect_cached_ram_block_address;
	wire inspect_state_is_dirty;
	wire inspect_state_is_writing;
	wire inspect_state_is_reading;

	wire busy;

	wire[xlen - 1:0] load_value;

	wire fast_store;
	wire[ram_block_width - 1:0] fast_store_value;

	wire slow_load;
	wire slow_store;
	wire[ram_block_address_width - 1:0] slow_address;

	ram_cache #(.rv64(rv64), .ram_block_width(ram_block_width)) ram_cache_module (
		.clock(clock), .reset(reset),
		.address(address), .ram_input(ram_input), .store_value(store_value),
		.fast_load_value(fast_load_value),
		.slow_busy(slow_busy), .slow_load_value(slow_load_value),

		.inspect_cached_ram_block_address(inspect_cached_ram_block_address), .inspect_state_is_dirty(inspect_state_is_dirty), .inspect_state_is_writing(inspect_state_is_writing), .inspect_state_is_reading(inspect_state_is_reading),
		.busy(busy),
		.load_value(load_value),
		.fast_store(fast_store), .fast_store_value(fast_store_value),
		.slow_load(slow_load), .slow_store(slow_store), .slow_address(slow_address)
	);

	initial begin
		clock = '0;
		reset = '0;
		ram_input = RamInput_None;

		if (rv64)
			fast_load_value = 128'h0123456701234567_89abcdef89abcdef;
		else
			fast_load_value = 64'h01234567_89abcdef;

		reset = '1;
		#1
		clock = '1;
		#1
		reset = '0;
		#1
		clock = '0;
		#1


		// Initial (cached, clean) -> (cached, clean)
		assert(inspect_cached_ram_block_address == 0) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		assert(busy == '0) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 0) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		assert(busy == '0) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;


		// Load from 0 (cached, clean) -> (cached, clean)
		#1
		clock = '0;
		address = 0;
		ram_input = RamInput_Load;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		if (rv64)
			assert(load_value == 64'h89abcdef89abcdef) else $fatal;
		else
			assert(load_value == 32'h89abcdef) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 0) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;


		// Load from 1 (cached, clean) -> (cached, clean)
		#1
		clock = '0;
		address = 1;
		ram_input = RamInput_Load;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		if (rv64)
			assert(load_value == 64'h0123456701234567) else $fatal;
		else
			assert(load_value == 32'h01234567) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 0) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;


		// Store to 0 (cached, clean) -> (cached, dirty)
		#1
		clock = '0;
		address = 0;
		ram_input = RamInput_Store;
		store_value = '1;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '1) else $fatal;
		if (rv64) begin
			assert(load_value == 64'h89abcdef89abcdef) else $fatal;
			assert(fast_store_value == 128'h0123456701234567_ffffffffffffffff) else $fatal;
		end else begin
			assert(load_value == 32'h89abcdef) else $fatal;
			assert(fast_store_value == 64'h01234567_ffffffff) else $fatal;
		end
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		if (rv64)
			assert(load_value == 64'h89abcdef89abcdef) else $fatal;
		else
			assert(load_value == 32'h89abcdef) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 0) else $fatal;
		assert(inspect_state_is_dirty == '1) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		#1
		if (rv64)
			fast_load_value = 128'h0123456701234567_ffffffffffffffff;
		else
			fast_load_value = 64'h01234567_ffffffff;


		// Load from 0 (cached, dirty) -> (cached, dirty)
		#1
		clock = '0;
		address = 0;
		ram_input = RamInput_Load;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		assert(load_value == '1) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 0) else $fatal;
		assert(inspect_state_is_dirty == '1) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;


		// Load from 5 (uncached, dirty) -> (cached, clean)
		#1
		clock = '0;
		address = 5;
		ram_input = RamInput_Load;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '1) else $fatal;
		assert(slow_address == 0) else $fatal;
		if (rv64)
			fast_load_value = 128'h0123456701234567_ffffffffffffffff;
		else
			fast_load_value = 64'h01234567_ffffffff;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 2) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '1) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		if (rv64)
			fast_load_value = 128'h0123456701234567_ffffffffffffffff;
		else
			fast_load_value = 64'h01234567_ffffffff;
		slow_busy = '1;
		#1
		clock = '0;
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		assert(inspect_cached_ram_block_address == 2) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '1) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		slow_busy = '0;
		#1
		clock = '0;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '1) else $fatal;
		assert(slow_store == '0) else $fatal;
		assert(slow_address == 2) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 2) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '1) else $fatal;
		slow_busy = '1;
		#1
		clock = '0;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 2) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '1) else $fatal;
		slow_busy = '0;
		if (rv64)
			slow_load_value = 128'hfedcba9876543210_fedcba9876543210;
		else
			slow_load_value = 64'hba987654_ba987654;
		#1
		clock = '0;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '1) else $fatal;
		if (rv64)
			assert(fast_store_value == 128'hfedcba9876543210_fedcba9876543210) else $fatal;
		else
			assert(fast_store_value == 64'hba987654_ba987654) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		if (rv64)
			fast_load_value = 128'hfedcba9876543210_fedcba9876543210;
		else
			fast_load_value = 64'hba987654_ba987654;
		#1
		assert(inspect_cached_ram_block_address == 2) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		#1
		clock = '0;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '0) else $fatal;
		if (rv64)
			assert(load_value == 64'hfedcba9876543210) else $fatal;
		else
			assert(load_value == 32'hba987654) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;


		// Store to 5 (cached, clean) -> (cached, dirty)
		#1
		clock = '0;
		address = 5;
		ram_input = RamInput_Store;
		store_value = '1;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '1) else $fatal;
		if (rv64)
			assert(fast_store_value == 128'hffffffffffffffff_fedcba9876543210) else $fatal;
		else
			assert(fast_store_value == 64'hffffffff_ba987654) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		if (rv64)
			assert(load_value == 64'hfedcba9876543210) else $fatal;
		else
			assert(load_value == 32'hba987654) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 2) else $fatal;
		assert(inspect_state_is_dirty == '1) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		#1
		if (rv64)
			fast_load_value = 128'hffffffffffffffff_fedcba9876543210;
		else
			fast_load_value = 64'hffffffff_ba987654;


		// Store to 9 (uncached, dirty) -> (cached, dirty)
		#1
		clock = '0;
		address = 9;
		ram_input = RamInput_Store;
		store_value = '1;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '1) else $fatal;
		assert(slow_address == 2) else $fatal;
		if (rv64)
			assert(fast_load_value == 128'hffffffffffffffff_fedcba9876543210) else $fatal;
		else
			assert(fast_load_value == 64'hffffffff_ba987654) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 4) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '1) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		slow_busy = '1;
		#1
		clock = '0;
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		assert(inspect_cached_ram_block_address == 4) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '1) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		slow_busy = '0;
		#1
		clock = '0;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '1) else $fatal;
		assert(slow_store == '0) else $fatal;
		assert(slow_address == 4) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 4) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '1) else $fatal;
		slow_busy = '1;
		#1
		clock = '0;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '0) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		#1
		assert(inspect_cached_ram_block_address == 4) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '1) else $fatal;
		slow_busy = '0;
		if (rv64)
			slow_load_value = 128'h0123456789abcdef_0123456789abcdef;
		else
			slow_load_value = 64'h456789ab_456789ab;
		#1
		clock = '0;
		#1
		assert(busy == '1) else $fatal;
		assert(fast_store == '1) else $fatal;
		if (rv64)
			assert(fast_store_value == 128'h0123456789abcdef_0123456789abcdef) else $fatal;
		else
			assert(fast_store_value == 64'h456789ab_456789ab) else $fatal;
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
		#1
		clock = '1;
		if (rv64)
			fast_load_value = 128'h0123456789abcdef_0123456789abcdef;
		else
			fast_load_value = 64'h456789ab_456789ab;
		#1
		assert(inspect_cached_ram_block_address == 4) else $fatal;
		assert(inspect_state_is_dirty == '0) else $fatal;
		assert(inspect_state_is_writing == '0) else $fatal;
		assert(inspect_state_is_reading == '0) else $fatal;
		#1
		clock = '0;
		#1
		assert(busy == '0) else $fatal;
		assert(fast_store == '1) else $fatal;
		if (rv64) begin
			assert(load_value == 64'h0123456789abcdef) else $fatal;
			assert(fast_store_value == 128'hffffffffffffffff_0123456789abcdef) else $fatal;
		end else begin
			assert(load_value == 32'h456789ab) else $fatal;
			assert(fast_store_value == 64'hffffffff_456789ab) else $fatal;
		end
		assert(slow_load == '0) else $fatal;
		assert(slow_store == '0) else $fatal;
	end
endmodule
`endif
