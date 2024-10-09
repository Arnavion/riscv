module load32 (
	input bit[1:0] address,
	input bit[2:0] funct3,
	input bit[31:0] ram_load_value,
	input bit[31:0] store_value,

	output bit efault,
	output logic[31:0] load_value,
	output logic[31:0] ram_store_value
);
	always_comb begin
		unique casez ({funct3, address})
			5'b?00_??,
			5'b?01_?0,
			5'b010_00: efault = '0;

			default: efault = '1;
		endcase

		if (efault) begin
			load_value = 'x;
			ram_store_value = 'x;

		end else begin
			load_value = 'x;

			unique case (address)
				2'b00: load_value[0+:32] = ram_load_value[0+:32];
				2'b01: load_value[0+:8] = ram_load_value[8+:8];
				2'b10: load_value[0+:16] = ram_load_value[16+:16];
				2'b11: load_value[0+:8] = ram_load_value[24+:8];
			endcase

			if (~funct3[0] & ~funct3[1]) // 0, 4
				load_value[8+:8] = {8{~funct3[2] & load_value[7]}};
			if (~funct3[1]) // 0, 1, 4, 5
				load_value[16+:16] = {16{~funct3[2] & load_value[15]}};

			if (funct3[2])
				ram_store_value = 'x;
			else begin
				ram_store_value = ram_load_value;

				unique casez ({funct3[0+:2], address})
					4'b00_00: ram_store_value[0+:8] = store_value[0+:8];
					4'b00_01: ram_store_value[8+:8] = store_value[0+:8];
					4'b00_10: ram_store_value[16+:8] = store_value[0+:8];
					4'b00_11: ram_store_value[24+:8] = store_value[0+:8];

					4'b01_0?: ram_store_value[0+:16] = store_value[0+:16];
					4'b01_1?: ram_store_value[16+:16] = store_value[0+:16];

					4'b10_??: ram_store_value[0+:32] = store_value[0+:32];

					default: ram_store_value = 'x;
				endcase
			end
		end
	end
endmodule

`ifdef TESTING
module test_load32;
	bit[1:0] address;
	bit[2:0] funct3;
	bit[31:0] ram_load_value;
	bit[31:0] store_value;
	wire efault;
	wire[31:0] load_value;
	wire[31:0] ram_store_value;
	load32 load32_module (
		address,
		funct3,
		ram_load_value,
		store_value,
		efault,
		load_value,
		ram_store_value
	);

	initial begin
		ram_load_value = 32'h456789ab;
		store_value = 32'hffffffff;

		// lb
		funct3 = 3'b000;

		address = 2'b00;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'hffffffab) else $fatal;
		assert(ram_store_value == 32'h456789ff) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'hffffff89) else $fatal;
		assert(ram_store_value == 32'h4567ffab) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00000067) else $fatal;
		assert(ram_store_value == 32'h45ff89ab) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00000045) else $fatal;
		assert(ram_store_value == 32'hff6789ab) else $fatal;

		// lbu
		funct3 = 3'b100;

		address = 2'b00;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h000000ab) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00000089) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00000067) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00000045) else $fatal;

		// lh
		funct3 = 3'b001;

		address = 2'b00;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'hffff89ab) else $fatal;
		assert(ram_store_value == 32'h4567ffff) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00004567) else $fatal;
		assert(ram_store_value == 32'hffff89ab) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b1) else $fatal;

		// lhu
		funct3 = 3'b101;

		address = 2'b00;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h000089ab) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h00004567) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b1) else $fatal;

		// lw
		funct3 = 3'b010;

		address = 2'b00;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 32'h456789ab) else $fatal;
		assert(ram_store_value == 32'hffffffff) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b1) else $fatal;

		// lwu
		funct3 = 3'b110;

		address = 2'b00;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b1) else $fatal;

		// ld
		funct3 = 3'b011;

		address = 2'b00;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b1) else $fatal;

		// ldu
		funct3 = 3'b111;

		address = 2'b00;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b01;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b10;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 2'b11;
		#1
		assert(efault == 1'b1) else $fatal;
	end
endmodule
`endif
