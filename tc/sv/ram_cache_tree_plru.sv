typedef enum bit[2:0] {
	RamInput_None = 3'b000,
	RamInput_Load = 3'b001,
	RamInput_Store = 3'b010,
	RamInput_Flush = 3'b100
} RamInput;


module ram_cache_tree_plru #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit clock,
	input bit reset,

	input bit cache_left_address_in_cache,
	input bit cache_right_address_in_cache,

	input RamInput ram_input,

	input logic cache_left_busy,
	input logic[xlen - 1:0] cache_left_load_value,

	input logic cache_right_busy,
	input logic[xlen - 1:0] cache_right_load_value,

	output bit address_in_cache,

	output bit busy,

	output logic[xlen - 1:0] load_value,

	output RamInput cache_left_ram_input,
	output RamInput cache_right_ram_input
);
	bit oldest;
	bit next_oldest;

	assign address_in_cache = cache_left_address_in_cache | cache_right_address_in_cache;

	assign busy = cache_left_busy | cache_right_busy;

	assign load_value =
		cache_left_address_in_cache ? cache_left_load_value :
		cache_right_address_in_cache ? cache_right_load_value :
		'x;

	always_ff @(posedge clock) begin
		if (reset)
			oldest <= '0;
		else
			oldest <= next_oldest;
	end

	always_comb begin
		unique casez ({ram_input == RamInput_Flush, cache_left_busy, cache_left_address_in_cache, cache_right_address_in_cache, oldest})
			5'b11???: begin
				cache_left_ram_input = ram_input;
				cache_right_ram_input = RamInput_None;
				next_oldest = oldest;
			end

			5'b10???: begin
				cache_left_ram_input = ram_input;
				cache_right_ram_input = ram_input;
				next_oldest = oldest;
			end

			5'b0?1??: begin
				cache_left_ram_input = ram_input;
				cache_right_ram_input = RamInput_None;
				next_oldest = '1;
			end

			5'b0?01?: begin
				cache_left_ram_input = RamInput_None;
				cache_right_ram_input = ram_input;
				next_oldest = '0;
			end

			5'b0?001: begin
				cache_left_ram_input = RamInput_None;
				cache_right_ram_input = ram_input;
				next_oldest = '0;
			end

			5'b0?000: begin
				cache_left_ram_input = ram_input;
				cache_right_ram_input = RamInput_None;
				next_oldest = '1;
			end
		endcase
	end
endmodule
