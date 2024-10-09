/*

+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Current | Load | Store | Flush |     Address     | Slow | -> |  Next   |  Next Address   | Busy |   Load Value    | Fast  |      Fast       | Slow | Slow  |      Slow       |
|  State  |      |       |       |                 | Busy | -> |  State  |                 |      |                 | Store |   Store Value   | Load | Store |     Address     |
+=========+======+=======+=======+=================+======+====+=========+=================+======+=================+=======+=================+======+=======+=================+
| Clean   | 0    | 0     |       |                 |      | -> | Clean   | Current Address | 0    |                 | 0     |                 | 0    | 0     |                 |
| Clean   | 1    | 0     | 0     | New Address     |      | -> | Reading | New Address     | 1    |                 | 0     |                 | 1    | 0     | New Address     |
| Clean   | 1    | 0     | 0     | Current Address |      | -> | Clean   | Current Address | 0    | Fast Load Value | 0     |                 | 0    | 0     |                 |
| Clean   | 0    | 1     | 0     | New Address     |      | -> | Reading | New Address     | 1    |                 | 0     |                 | 1    | 0     | New Address     |
| Clean   | 0    | 1     | 0     | Current Address |      | -> | Dirty   | Current Address | 0    | Fast Load Value | 1     | Store Value     | 0    | 0     |                 |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Dirty   | 0    | 0     | 0     |                 |      | -> | Dirty   | Current Address | 0    |                 | 0     |                 | 0    | 0     |                 |
| Dirty   | 1    | 0     | 0     | New Address     |      | -> | Writing | New Address     | 1    |                 | 0     |                 | 0    | 1     | Current Address |
| Dirty   | 1    | 0     | 0     | Current Address |      | -> | Dirty   | Current Address | 0    | Fast Load Value | 0     |                 | 0    | 0     |                 |
| Dirty   | 0    | 1     | 0     | New Address     |      | -> | Writing | New Address     | 1    |                 | 0     |                 | 0    | 1     | Current Address |
| Dirty   | 0    | 1     | 0     | Current Address |      | -> | Dirty   | Current Address | 0    | Fast Load Value | 1     | Store Value     | 0    | 0     |                 |
| Dirty   | 0    | 0     | 1     |                 |      | -> | Writing | Current Address | 1    |                 | 0     |                 | 0    | 1     | Current Address |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Writing |      |       |       |                 | 1    | -> | Writing | Current Address | 1    |                 | 0     |                 | 0    | 0     |                 |
| Writing | 1    | 0     | 0     |                 | 0    | -> | Reading | Current Address | 1    |                 | 0     |                 | 1    | 0     | Current Address |
| Writing | 0    | 1     | 0     |                 | 0    | -> | Reading | Current Address | 1    |                 | 0     |                 | 1    | 0     | Current Address |
| Writing | 0    | 0     | 1     |                 | 0    | -> | Clean   | Current Address | 0    |                 | 0     |                 | 0    | 0     |                 |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+
| Reading |      |       |       |                 | 1    | -> | Reading | Current Address | 1    |                 | 0     |                 | 0    | 0     |                 |
| Reading | 1    | 0     | 0     |                 | 0    | -> | Clean   | Current Address | 0    | Slow Load Value | 1     | Slow Load Value | 0    | 0     |                 |
| Reading | 0    | 1     | 0     |                 | 0    | -> | Dirty   | Current Address | 0    | Slow Load Value | 1     | Store Value     | 0    | 0     |                 |
+---------+------+-------+-------+-----------------+------+----+---------+-----------------+------+-----------------+-------+-----------------+------+-------+-----------------+

 */

module ram_cache #(
	parameter data_width = 512,
	localparam address_width = 67 - $clog2(data_width),
	localparam block_address_width = 61 - address_width
) (
	input bit clock,

	input logic[address_width + block_address_width - 1:0] address,
	input bit load,
	input bit store,
	input logic[63:0] store_value,
	input bit flush,

	input logic[data_width - 1:0] fast_load_value,

	input bit slow_busy,
	input logic[data_width - 1:0] slow_load_value,

	output bit[address_width - 1:0] inspect_cached_address,
	output bit inspect_state_is_dirty,
	output bit inspect_state_is_writing,
	output bit inspect_state_is_reading,

	output bit busy,

	output logic[63:0] load_value,

	output bit fast_store,
	output logic[data_width - 1:0] fast_store_value,

	output bit slow_load,
	output bit slow_store,
	output logic[address_width - 1:0] slow_address
);
	typedef enum logic[1:0] {
		State_Clean,
		State_Dirty,
		State_Writing,
		State_Reading
	} State;

	State state = State_Clean;
	bit[address_width - 1:0] cached_address = '0;

	State next_state;
	bit[address_width - 1:0] next_cached_address;

	always_ff @(posedge clock) begin
		state <= next_state;
		cached_address <= next_cached_address;
	end

	always_comb begin
		next_cached_address = 'x;

		inspect_cached_address = cached_address;
		inspect_state_is_dirty = state == State_Dirty;
		inspect_state_is_writing = state == State_Writing;
		inspect_state_is_reading = state == State_Reading;

		busy = '0;
		load_value = 'x;
		fast_store = '0;
		fast_store_value = 'x;
		slow_load = '0;
		slow_store = '0;
		slow_address = 'x;

		unique casez ({ state, load, store, flush, address[block_address_width+:address_width] == cached_address, slow_busy })
			{State_Clean, 5'b00???}: begin
				next_state = State_Clean;
				next_cached_address = cached_address;
			end

			{State_Clean, 5'b1000?}: begin
				next_state = State_Reading;
				next_cached_address = address[block_address_width+:address_width];
				busy = '1;
				slow_load = '1;
				slow_address = address[block_address_width+:address_width];
			end

			{State_Clean, 5'b1001?}: begin
				next_state = State_Clean;
				next_cached_address = cached_address;
				load_value = fast_load_value[{address[0+:block_address_width], 6'b0}+:64];
			end

			{State_Clean, 5'b0100?}: begin
				next_state = State_Reading;
				next_cached_address = address[block_address_width+:address_width];
				busy = '1;
				slow_load = '1;
				slow_address = address[block_address_width+:address_width];
			end

			{State_Clean, 5'b0101?}: begin
				next_state = State_Dirty;
				next_cached_address = cached_address;
				load_value = fast_load_value[{address[0+:block_address_width], 6'b0}+:64];
				fast_store = '1;
				fast_store_value = fast_load_value;
				fast_store_value[{address[0+:block_address_width], 6'b0}+:64] = store_value;
			end

			{State_Dirty, 5'b000??}: begin
				next_state = State_Dirty;
				next_cached_address = cached_address;
			end

			{State_Dirty, 5'b1000?}: begin
				next_state = State_Writing;
				next_cached_address = address[block_address_width+:address_width];
				busy = '1;
				slow_store = '1;
				slow_address = cached_address;
			end

			{State_Dirty, 5'b1001?}: begin
				next_state = State_Dirty;
				next_cached_address = cached_address;
				load_value = fast_load_value[{address[0+:block_address_width], 6'b0}+:64];
			end

			{State_Dirty, 5'b0100?}: begin
				next_state = State_Writing;
				next_cached_address = address[block_address_width+:address_width];
				busy = '1;
				slow_store = '1;
				slow_address = cached_address;
			end

			{State_Dirty, 5'b0101?}: begin
				next_state = State_Dirty;
				next_cached_address = cached_address;
				load_value = fast_load_value[{address[0+:block_address_width], 6'b0}+:64];
				fast_store = '1;
				fast_store_value = fast_load_value;
				fast_store_value[{address[0+:block_address_width], 6'b0}+:64] = store_value;
			end

			{State_Dirty, 5'b001??}: begin
				next_state = State_Writing;
				next_cached_address = cached_address;
				busy = '1;
				slow_store = '1;
				slow_address = cached_address;
			end

			{State_Writing, 5'b????1}: begin
				next_state = State_Writing;
				next_cached_address = cached_address;
				busy = '1;
			end

			{State_Writing, 5'b100?0}: begin
				next_state = State_Reading;
				next_cached_address = cached_address;
				busy = '1;
				slow_load = '1;
				slow_address = cached_address;
			end

			{State_Writing, 5'b010?0}: begin
				next_state = State_Reading;
				next_cached_address = cached_address;
				busy = '1;
				slow_load = '1;
				slow_address = cached_address;
			end

			{State_Writing, 5'b001?0}: begin
				next_state = State_Clean;
				next_cached_address = cached_address;
			end

			{State_Reading, 5'b????1}: begin
				next_state = State_Reading;
				next_cached_address = cached_address;
				busy = '1;
			end

			{State_Reading, 5'b100?0}: begin
				next_state = State_Clean;
				load_value = slow_load_value[{address[0+:block_address_width], 6'b0}+:64];
				fast_store = '1;
				fast_store_value = slow_load_value;
			end

			{State_Reading, 5'b010?0}: begin
				next_state = State_Dirty;
				load_value = slow_load_value[{address[0+:block_address_width], 6'b0}+:64];
				fast_store = '1;
				fast_store_value = slow_load_value;
				fast_store_value[{address[0+:block_address_width], 6'b0}+:64] = store_value;
			end

			default: $stop;
		endcase
	end
endmodule
