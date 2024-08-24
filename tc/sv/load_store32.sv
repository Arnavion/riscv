module load_store32 (
	input bit[1:0] address,
	input bit[2:0] funct3,
	input bit[3:0][7:0] ram_load_value,
	input bit[3:0][7:0] store_value,

	output bit efault,
	output logic[3:0][7:0] load_value,
	output logic[3:0][7:0] ram_store_value
);
	bit[3:0] address2_decoded;
	bit[3:0] store_mask;
	bit[3:0][7:0] store_value_shifted;

	always_comb begin
		unique case (funct3[0+:2])
			2'b00: efault = '0;
			2'b01: efault = address[0];
			2'b10: efault = (| address) | funct3[2];
			2'b11: efault = '1;
		endcase

		if (efault) begin
			load_value = 'x;
			address2_decoded = 'x;
			store_mask = 'x;
			store_value_shifted = 'x;
			ram_store_value = 'x;

		end else begin
			load_value = ram_load_value;
			if (address[1])
				load_value = {16'bx, load_value[2+:2]};
			if (address[0])
				load_value = {8'bx, load_value[1+:3]};

			unique case (funct3[0+:2])
				2'b00: load_value[1+:3] = {24{~funct3[2] & load_value[0][7]}};
				2'b01: load_value[2+:2] = {16{~funct3[2] & load_value[1][7]}};
				2'b10: ;
				2'b11: load_value = 'x;
			endcase

			if (funct3[2]) begin
				address2_decoded = 'x;
				store_mask = 'x;
				store_value_shifted = 'x;
				ram_store_value = 'x;

			end else begin
				// store_mask = {
				//     {funct3[0+:2], address} inside {4'b10_??, 4'b01_1?, 4'b00_11},
				//     {funct3[0+:2], address} inside {4'b10_??, 4'b01_1?, 4'b00_10},
				//     {funct3[0+:2], address} inside {4'b10_??, 4'b01_0?, 4'b00_01},
				//     {funct3[0+:2], address} inside {4'b10_??, 4'b01_0?, 4'b00_00}
				// };
				address2_decoded = {
					& address,
					~(address[0] | (~| address)),
					~(address[1] | (~| address)),
					~| address
				};
				store_mask =
					{4{funct3[1]}} |
					({4{funct3[0]}} & {address2_decoded[2], address2_decoded[3], address2_decoded[0], address2_decoded[1]}) |
					address2_decoded;

				unique case (funct3[0+:2])
					2'b00: store_value_shifted = {4{store_value[0]}};
					2'b01: store_value_shifted = {2{store_value[0+:2]}};
					2'b10: store_value_shifted = store_value;
					2'b11: store_value_shifted = 'x;
				endcase

				foreach (ram_store_value[i])
					ram_store_value[i] = store_mask[i] ? store_value_shifted[i] : ram_load_value[i];
			end
		end
	end
endmodule

`ifdef TESTING
module test_load_store32;
	bit[1:0] address;
	bit[2:0] funct3;
	bit[31:0] ram_load_value;
	bit[31:0] store_value;
	wire efault;
	wire[31:0] load_value;
	wire[31:0] ram_store_value;
	load_store32 load_store32_module (
		.address(address),
		.funct3(funct3),
		.ram_load_value(ram_load_value),
		.store_value(store_value),
		.efault(efault),
		.load_value(load_value),
		.ram_store_value(ram_store_value)
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
