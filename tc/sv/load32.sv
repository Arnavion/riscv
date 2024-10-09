module load32 (
	input bit[1:0] address,
	input bit[2:0] funct3,
	input bit[31:0] ram_load_value,
	input bit[31:0] store_value,

	output bit efault,
	output logic[31:0] load_value,
	output logic[31:0] ram_store_value
);
	bit[31:0] store_mask;
	bit[31:0] store_value_masked;

	always_comb begin
		load_value = ram_load_value >> {address, 3'b000};

		store_mask = {
			{16{funct3[1]}}, // lw
			{8{| funct3[0+:2]}}, // lh(u), lw
			{8{1'b1}} // lb(u), lh(u), lw
		};
		store_value_masked = store_value & store_mask;

		store_value_masked <<= {address[0+:2], 3'b000};
		store_mask <<= {address[0+:2], 3'b000};

		if (~| funct3[0+:2]) // lb(u)
			load_value[8+:8] = {8{~funct3[2] & load_value[7]}};
		if (~funct3[1]) // lb(u), lh(u)
			load_value[16+:16] = {16{~funct3[2] & load_value[15]}};

		ram_store_value = (ram_load_value & ~store_mask) | store_value_masked;

		unique casez (funct3[0+:2])
			2'b00: efault = '0;
			2'b01: efault = address[0];
			2'b10: efault = (| address) | funct3[2];
			2'b11: efault = '1;
		endcase

		if (funct3[2])
			ram_store_value = 'x;

		if (efault == '1) begin
			load_value = 'x;
			ram_store_value = 'x;
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
