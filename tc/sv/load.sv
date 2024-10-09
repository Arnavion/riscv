module load (
	input bit[2:0] address,
	input bit[2:0] funct3,
	input bit[63:0] ram_load_value,
	input bit[63:0] store_value,

	output bit efault,
	output logic[63:0] load_value,
	output logic[63:0] ram_store_value
);
	bit[5:0] bit_start_index;

	always_comb begin
		bit_start_index = {address, 3'b0};

		unique casez ({funct3, address})
			{6'b000_???}: begin
				efault = '0;
				load_value = {{56{ram_load_value[bit_start_index + 7]}}, ram_load_value[bit_start_index+:8]};
				ram_store_value = ram_load_value;
				ram_store_value[bit_start_index+:8] = store_value[0+:8];
			end

			{6'b001_??0}: begin
				efault = '0;
				load_value = {{48{ram_load_value[bit_start_index + 15]}}, ram_load_value[bit_start_index+:16]};
				ram_store_value = ram_load_value;
				ram_store_value[bit_start_index+:16] = store_value[0+:16];
			end

			{6'b010_?00}: begin
				efault = '0;
				load_value = {{32{ram_load_value[bit_start_index + 31]}}, ram_load_value[bit_start_index+:32]};
				ram_store_value = ram_load_value;
				ram_store_value[bit_start_index+:32] = store_value[0+:32];
			end

			{6'b011_000}: begin
				efault = '0;
				load_value = ram_load_value;
				ram_store_value = ram_load_value;
				ram_store_value = store_value;
			end

			{6'b100_???}: begin
				efault = '0;
				load_value = {56'b0, ram_load_value[bit_start_index+:8]};
				ram_store_value = 'x;
			end

			{6'b101_??0}: begin
				efault = '0;
				load_value = {48'b0, ram_load_value[bit_start_index+:16]};
				ram_store_value = 'x;
			end

			{6'b110_?00}: begin
				efault = '0;
				load_value = {32'b0, ram_load_value[bit_start_index+:32]};
				ram_store_value = 'x;
			end

			default: begin
				efault = '1;
				load_value = 'x;
				ram_store_value = 'x;
			end
		endcase
	end
endmodule
