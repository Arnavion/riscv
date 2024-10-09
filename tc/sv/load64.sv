module load64 (
	input bit[2:0] address,
	input bit[2:0] funct3,
	input bit[63:0] ram_load_value,
	input bit[63:0] store_value,

	output bit efault,
	output logic[63:0] load_value,
	output logic[63:0] ram_store_value
);
	always_comb begin
		unique casez ({funct3, address})
			6'b?00_???,
			6'b?01_??0,
			6'b?10_?00,
			6'b011_000: efault = '0;

			default: efault = '1;
		endcase

		if (efault) begin
			load_value = 'x;
			ram_store_value = 'x;

		end else begin
			load_value = 'x;

			unique case (address)
				3'b000: load_value[0+:64] = ram_load_value[0+:64];
				3'b001: load_value[0+:8] = ram_load_value[8+:8];
				3'b010: load_value[0+:16] = ram_load_value[16+:16];
				3'b011: load_value[0+:8] = ram_load_value[24+:8];
				3'b100: load_value[0+:32] = ram_load_value[32+:32];
				3'b101: load_value[0+:8] = ram_load_value[40+:8];
				3'b110: load_value[0+:16] = ram_load_value[48+:16];
				3'b111: load_value[0+:8] = ram_load_value[56+:8];
			endcase

			if (~funct3[0] & ~funct3[1]) // 0, 4
				load_value[8+:8] = {8{~funct3[2] & load_value[7]}};
			if (~funct3[1]) // 0, 1, 4, 5
				load_value[16+:16] = {16{~funct3[2] & load_value[15]}};
			if (~funct3[0] | ~funct3[1]) // 0, 1, 2, 4, 5, 6
				load_value[32+:32] = {32{~funct3[2] & load_value[31]}};

			if (funct3[2])
				ram_store_value = 'x;
			else begin
				ram_store_value = ram_load_value;

				unique casez ({funct3[0+:2], address})
					5'b00_000: ram_store_value[0+:8] = store_value[0+:8];
					5'b00_001: ram_store_value[8+:8] = store_value[0+:8];
					5'b00_010: ram_store_value[16+:8] = store_value[0+:8];
					5'b00_011: ram_store_value[24+:8] = store_value[0+:8];
					5'b00_100: ram_store_value[32+:8] = store_value[0+:8];
					5'b00_101: ram_store_value[40+:8] = store_value[0+:8];
					5'b00_110: ram_store_value[48+:8] = store_value[0+:8];
					5'b00_111: ram_store_value[56+:8] = store_value[0+:8];

					5'b01_00?: ram_store_value[0+:16] = store_value[0+:16];
					5'b01_01?: ram_store_value[16+:16] = store_value[0+:16];
					5'b01_10?: ram_store_value[32+:16] = store_value[0+:16];
					5'b01_11?: ram_store_value[48+:16] = store_value[0+:16];

					5'b10_0??: ram_store_value[0+:32] = store_value[0+:32];
					5'b10_1??: ram_store_value[32+:32] = store_value[0+:32];

					5'b11_???: ram_store_value[0+:64] = store_value[0+:64];
				endcase
			end
		end
	end
endmodule

`ifdef TESTING
module test_load64;
	bit[2:0] address;
	bit[2:0] funct3;
	bit[63:0] ram_load_value;
	bit[63:0] store_value;
	wire efault;
	wire[63:0] load_value;
	wire[63:0] ram_store_value;
	load64 load64_module (
		address,
		funct3,
		ram_load_value,
		store_value,
		efault,
		load_value,
		ram_store_value
	);

	initial begin
		ram_load_value = 64'h0123456789abcdef;
		store_value = 64'hffffffffffffffff;

		// lb
		funct3 = 3'b000;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffffffffffef) else $fatal;
		assert(ram_store_value == 64'h0123456789abcdff) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffffffffffcd) else $fatal;
		assert(ram_store_value == 64'h0123456789abffef) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffffffffffab) else $fatal;
		assert(ram_store_value == 64'h0123456789ffcdef) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffffffffff89) else $fatal;
		assert(ram_store_value == 64'h01234567ffabcdef) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000067) else $fatal;
		assert(ram_store_value == 64'h012345ff89abcdef) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000045) else $fatal;
		assert(ram_store_value == 64'h0123ff6789abcdef) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000023) else $fatal;
		assert(ram_store_value == 64'h01ff456789abcdef) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000001) else $fatal;
		assert(ram_store_value == 64'hff23456789abcdef) else $fatal;

		// lbu
		funct3 = 3'b100;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h00000000000000ef) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h00000000000000cd) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h00000000000000ab) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000089) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000067) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000045) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000023) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000001) else $fatal;

		// lh
		funct3 = 3'b001;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffffffffcdef) else $fatal;
		assert(ram_store_value == 64'h0123456789abffff) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffffffff89ab) else $fatal;
		assert(ram_store_value == 64'h01234567ffffcdef) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000004567) else $fatal;
		assert(ram_store_value == 64'h0123ffff89abcdef) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000123) else $fatal;
		assert(ram_store_value == 64'hffff456789abcdef) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b1) else $fatal;

		// lhu
		funct3 = 3'b101;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h000000000000cdef) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h00000000000089ab) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000004567) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000000000123) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b1) else $fatal;

		// lw
		funct3 = 3'b010;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'hffffffff89abcdef) else $fatal;
		assert(ram_store_value == 64'h01234567ffffffff) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000001234567) else $fatal;
		assert(ram_store_value == 64'hffffffff89abcdef) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b1) else $fatal;

		// lwu
		funct3 = 3'b110;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000089abcdef) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0000000001234567) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b1) else $fatal;

		// ld
		funct3 = 3'b011;

		address = 3'b000;
		#1
		assert(efault == 1'b0) else $fatal;
		assert(load_value == 64'h0123456789abcdef) else $fatal;
		assert(ram_store_value == 64'hffffffffffffffff) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b1) else $fatal;

		// ldu
		funct3 = 3'b111;

		address = 3'b000;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b001;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b010;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b011;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b100;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b101;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b110;
		#1
		assert(efault == 1'b1) else $fatal;

		address = 3'b111;
		#1
		assert(efault == 1'b1) else $fatal;
	end
endmodule
`endif
