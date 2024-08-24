module load_store64 (
	input bit[2:0] address,
	input bit[2:0] funct3,
	input bit[7:0][7:0] ram_load_value,
	input bit[7:0][7:0] store_value,

	output bit efault,
	output logic[7:0][7:0] load_value,
	output logic[7:0][7:0] ram_store_value
);
	bit[1:0] address1_decoded;
	bit[3:0] address2_decoded;
	bit[7:0] address3_decoded;
	bit[7:0] store_mask;
	bit[7:0][7:0] store_value_shifted;

	always_comb begin
		unique case (funct3[0+:2])
			2'b00: efault = '0;
			2'b01: efault = address[0];
			2'b10: efault = | address[0+:2];
			2'b11: efault = (| address) | funct3[2];
		endcase

		if (efault) begin
			load_value = 'x;
			address1_decoded = 'x;
			address2_decoded = 'x;
			address3_decoded = 'x;
			store_mask = 'x;
			store_value_shifted = 'x;
			ram_store_value = 'x;

		end else begin
			load_value = ram_load_value;
			if (address[0])
				load_value = {8'bx, load_value[1+:7]};
			if (address[1])
				load_value = {16'bx, load_value[2+:6]};
			if (address[2])
				load_value = {32'bx, load_value[4+:4]};

			unique case (funct3[0+:2])
				2'b00: load_value[1+:7] = {56{~funct3[2] & load_value[0][7]}};
				2'b01: load_value[2+:6] = {48{~funct3[2] & load_value[1][7]}};
				2'b10: load_value[4+:4] = {32{~funct3[2] & load_value[3][7]}};
				2'b11: ;
			endcase

			if (funct3[2]) begin
				address1_decoded = 'x;
				address2_decoded = 'x;
				address3_decoded = 'x;
				store_mask = 'x;
				store_value_shifted = 'x;
				ram_store_value = 'x;

			end else begin
				// store_mask = {
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_1??, 5'b01_11?, 5'b00_111},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_1??, 5'b01_11?, 5'b00_110},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_1??, 5'b01_10?, 5'b00_101},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_1??, 5'b01_10?, 5'b00_100},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_0??, 5'b01_01?, 5'b00_011},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_0??, 5'b01_01?, 5'b00_010},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_0??, 5'b01_00?, 5'b00_001},
				//     {funct3[0+:2], address} inside {5'b11_???, 5'b10_0??, 5'b01_00?, 5'b00_000}
				// };
				address1_decoded = {
					address[2],
					~address[2]
				};
				address2_decoded = {
					{2{address1_decoded[1]}},
					{2{address1_decoded[0]}}
				} & {2{
					address[1],
					~address[1]
				}};
				address3_decoded = {
					{2{address2_decoded[3]}},
					{2{address2_decoded[2]}},
					{2{address2_decoded[1]}},
					{2{address2_decoded[0]}}
				} & {4{
					address[0],
					~address[0]
				}};
				store_mask =
					{8{& funct3[0+:2]}} |
					({8{funct3[1]}} & {{4{address1_decoded[1]}}, {4{address1_decoded[0]}}}) |
					({8{funct3[0]}} & {{2{address2_decoded[3]}}, {2{address2_decoded[2]}}, {2{address2_decoded[1]}}, {2{address2_decoded[0]}}}) |
					address3_decoded;

				unique case (funct3[0+:2])
					2'b00: store_value_shifted = {8{store_value[0]}};
					2'b01: store_value_shifted = {4{store_value[0+:2]}};
					2'b10: store_value_shifted = {2{store_value[0+:4]}};
					2'b11: store_value_shifted = store_value;
				endcase

				foreach (ram_store_value[i])
					ram_store_value[i] = store_mask[i] ? store_value_shifted[i] : ram_load_value[i];
			end
		end
	end
endmodule

`ifdef TESTING
module test_load_store64;
	bit[2:0] address;
	bit[2:0] funct3;
	bit[63:0] ram_load_value;
	bit[63:0] store_value;
	wire efault;
	wire[63:0] load_value;
	wire[63:0] ram_store_value;
	load_store64 load_store64_module (
		.address(address),
		.funct3(funct3),
		.ram_load_value(ram_load_value),
		.store_value(store_value),
		.efault(efault),
		.load_value(load_value),
		.ram_store_value(ram_store_value)
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
