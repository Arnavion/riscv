module rv_register_file (
	input bit clock,

	input bit[31:0] rd,
	input bit[31:0] rs1,
	input bit[31:0] rs2,

	input logic[31:0] rd_value,

	output logic [31:0] rs1_value,
	output logic [31:0] rs2_value
);
	// TODO:
	// Would be nice to do `bit [31:0] registers[31:1] = '{31{'0}};` but yosys doesn't support the cast.
	// Alternative is `bit [31:0] registers[31:1] = {'0, '0, '0, ...};` but yosys rejects that
	// with a baroque "invalid array index" error.
	bit[31:0] x1 = '0;
	bit[31:0] x2 = '0;
	bit[31:0] x3 = '0;
	bit[31:0] x4 = '0;
	bit[31:0] x5 = '0;
	bit[31:0] x6 = '0;
	bit[31:0] x7 = '0;
	bit[31:0] x8 = '0;
	bit[31:0] x9 = '0;
	bit[31:0] x10 = '0;
	bit[31:0] x11 = '0;
	bit[31:0] x12 = '0;
	bit[31:0] x13 = '0;
	bit[31:0] x14 = '0;
	bit[31:0] x15 = '0;
	bit[31:0] x16 = '0;
	bit[31:0] x17 = '0;
	bit[31:0] x18 = '0;
	bit[31:0] x19 = '0;
	bit[31:0] x20 = '0;
	bit[31:0] x21 = '0;
	bit[31:0] x22 = '0;
	bit[31:0] x23 = '0;
	bit[31:0] x24 = '0;
	bit[31:0] x25 = '0;
	bit[31:0] x26 = '0;
	bit[31:0] x27 = '0;
	bit[31:0] x28 = '0;
	bit[31:0] x29 = '0;
	bit[31:0] x30 = '0;
	bit[31:0] x31 = '0;

	always_ff @(posedge clock) begin
		unique case (rd)
			32'b00000000000000000000000000000000: ;
			32'b00000000000000000000000000000001: ;
			32'b00000000000000000000000000000010: x1 <= rd_value;
			32'b00000000000000000000000000000100: x2 <= rd_value;
			32'b00000000000000000000000000001000: x3 <= rd_value;
			32'b00000000000000000000000000010000: x4 <= rd_value;
			32'b00000000000000000000000000100000: x5 <= rd_value;
			32'b00000000000000000000000001000000: x6 <= rd_value;
			32'b00000000000000000000000010000000: x7 <= rd_value;
			32'b00000000000000000000000100000000: x8 <= rd_value;
			32'b00000000000000000000001000000000: x9 <= rd_value;
			32'b00000000000000000000010000000000: x10 <= rd_value;
			32'b00000000000000000000100000000000: x11 <= rd_value;
			32'b00000000000000000001000000000000: x12 <= rd_value;
			32'b00000000000000000010000000000000: x13 <= rd_value;
			32'b00000000000000000100000000000000: x14 <= rd_value;
			32'b00000000000000001000000000000000: x15 <= rd_value;
			32'b00000000000000010000000000000000: x16 <= rd_value;
			32'b00000000000000100000000000000000: x17 <= rd_value;
			32'b00000000000001000000000000000000: x18 <= rd_value;
			32'b00000000000010000000000000000000: x19 <= rd_value;
			32'b00000000000100000000000000000000: x20 <= rd_value;
			32'b00000000001000000000000000000000: x21 <= rd_value;
			32'b00000000010000000000000000000000: x22 <= rd_value;
			32'b00000000100000000000000000000000: x23 <= rd_value;
			32'b00000001000000000000000000000000: x24 <= rd_value;
			32'b00000010000000000000000000000000: x25 <= rd_value;
			32'b00000100000000000000000000000000: x26 <= rd_value;
			32'b00001000000000000000000000000000: x27 <= rd_value;
			32'b00010000000000000000000000000000: x28 <= rd_value;
			32'b00100000000000000000000000000000: x29 <= rd_value;
			32'b01000000000000000000000000000000: x30 <= rd_value;
			32'b10000000000000000000000000000000: x31 <= rd_value;
			default: $stop;
		endcase
	end

	always_comb begin
		rs1_value = 'x;
		unique case (rs1)
			32'b00000000000000000000000000000000: ;
			32'b00000000000000000000000000000001: rs1_value = '0;
			32'b00000000000000000000000000000010: rs1_value = x1;
			32'b00000000000000000000000000000100: rs1_value = x2;
			32'b00000000000000000000000000001000: rs1_value = x3;
			32'b00000000000000000000000000010000: rs1_value = x4;
			32'b00000000000000000000000000100000: rs1_value = x5;
			32'b00000000000000000000000001000000: rs1_value = x6;
			32'b00000000000000000000000010000000: rs1_value = x7;
			32'b00000000000000000000000100000000: rs1_value = x8;
			32'b00000000000000000000001000000000: rs1_value = x9;
			32'b00000000000000000000010000000000: rs1_value = x10;
			32'b00000000000000000000100000000000: rs1_value = x11;
			32'b00000000000000000001000000000000: rs1_value = x12;
			32'b00000000000000000010000000000000: rs1_value = x13;
			32'b00000000000000000100000000000000: rs1_value = x14;
			32'b00000000000000001000000000000000: rs1_value = x15;
			32'b00000000000000010000000000000000: rs1_value = x16;
			32'b00000000000000100000000000000000: rs1_value = x17;
			32'b00000000000001000000000000000000: rs1_value = x18;
			32'b00000000000010000000000000000000: rs1_value = x19;
			32'b00000000000100000000000000000000: rs1_value = x20;
			32'b00000000001000000000000000000000: rs1_value = x21;
			32'b00000000010000000000000000000000: rs1_value = x22;
			32'b00000000100000000000000000000000: rs1_value = x23;
			32'b00000001000000000000000000000000: rs1_value = x24;
			32'b00000010000000000000000000000000: rs1_value = x25;
			32'b00000100000000000000000000000000: rs1_value = x26;
			32'b00001000000000000000000000000000: rs1_value = x27;
			32'b00010000000000000000000000000000: rs1_value = x28;
			32'b00100000000000000000000000000000: rs1_value = x29;
			32'b01000000000000000000000000000000: rs1_value = x30;
			32'b10000000000000000000000000000000: rs1_value = x31;
			default: $stop;
		endcase

		rs2_value = 'x;
		unique case (rs2)
			32'b00000000000000000000000000000000: ;
			32'b00000000000000000000000000000001: rs2_value = '0;
			32'b00000000000000000000000000000010: rs2_value = x1;
			32'b00000000000000000000000000000100: rs2_value = x2;
			32'b00000000000000000000000000001000: rs2_value = x3;
			32'b00000000000000000000000000010000: rs2_value = x4;
			32'b00000000000000000000000000100000: rs2_value = x5;
			32'b00000000000000000000000001000000: rs2_value = x6;
			32'b00000000000000000000000010000000: rs2_value = x7;
			32'b00000000000000000000000100000000: rs2_value = x8;
			32'b00000000000000000000001000000000: rs2_value = x9;
			32'b00000000000000000000010000000000: rs2_value = x10;
			32'b00000000000000000000100000000000: rs2_value = x11;
			32'b00000000000000000001000000000000: rs2_value = x12;
			32'b00000000000000000010000000000000: rs2_value = x13;
			32'b00000000000000000100000000000000: rs2_value = x14;
			32'b00000000000000001000000000000000: rs2_value = x15;
			32'b00000000000000010000000000000000: rs2_value = x16;
			32'b00000000000000100000000000000000: rs2_value = x17;
			32'b00000000000001000000000000000000: rs2_value = x18;
			32'b00000000000010000000000000000000: rs2_value = x19;
			32'b00000000000100000000000000000000: rs2_value = x20;
			32'b00000000001000000000000000000000: rs2_value = x21;
			32'b00000000010000000000000000000000: rs2_value = x22;
			32'b00000000100000000000000000000000: rs2_value = x23;
			32'b00000001000000000000000000000000: rs2_value = x24;
			32'b00000010000000000000000000000000: rs2_value = x25;
			32'b00000100000000000000000000000000: rs2_value = x26;
			32'b00001000000000000000000000000000: rs2_value = x27;
			32'b00010000000000000000000000000000: rs2_value = x28;
			32'b00100000000000000000000000000000: rs2_value = x29;
			32'b01000000000000000000000000000000: rs2_value = x30;
			32'b10000000000000000000000000000000: rs2_value = x31;
			default: $stop;
		endcase
	end
endmodule