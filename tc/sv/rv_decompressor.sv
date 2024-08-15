/*

# MISC-ALU

Zca

+----------------+-----------------------------------------+---------------------------------------------------------------------------------------+
|   Instruction  |               Compressed                |                                    Decompressed                                       |
|                | [12] | [11:10] | [9:7]  | [6:5] | [4:2] | [31:26] | [25] | [24:20] | [19:15] | [14:12] | [11:7] | [6] | [5] | [4] | [3] | [2:0] |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+
| c.srli rd, imm | I    | 00      | rd/rs1 | II    | III   | 000000  | I    | IIIII   | rd      | 101     | rd     | 0   | 0   | 1   | 0   | 011   |
| c.srai rd, imm | I    | 01      | rd/rs1 | II    | III   | 010000  | I    | IIIII   | rd      | 101     | rd     | 0   | 0   | 1   | 0   | 011   |
| c.andi rd, imm | I    | 10      | rd/rs1 | II    | III   | IIIIII  | I    | IIIII   | rd      | 111     | rd     | 0   | 0   | 1   | 0   | 011   |
| c.sub rd, rs2  | 0    | 11      | rd/rs1 | 00    | rs2   | 010000  | 0    | rs2     | rd      | 000     | rd     | 0   | 1   | 1   | 0   | 011   |
| c.xor rd, rs2  | 0    | 11      | rd/rs1 | 01    | rs2   | 000000  | 0    | rs2     | rd      | 100     | rd     | 0   | 1   | 1   | 0   | 011   |
| c.or rd, rs2   | 0    | 11      | rd/rs1 | 10    | rs2   | 000000  | 0    | rs2     | rd      | 110     | rd     | 0   | 1   | 1   | 0   | 011   |
| c.and rd, rs2  | 0    | 11      | rd/rs1 | 11    | rs2   | 000000  | 0    | rs2     | rd      | 111     | rd     | 0   | 1   | 1   | 0   | 011   |
| c.subw rd, rs2 | 1    | 11      | rd/rs1 | 00    | rs2   | 010000  | 0    | rs2     | rd      | 000     | rd     | 0   | 1   | 1   | 1   | 011   |
| c.addw rd, rs2 | 1    | 11      | rd/rs1 | 01    | rs2   | 000000  | 0    | rs2     | rd      | 000     | rd     | 0   | 1   | 1   | 1   | 011   |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+

                                                                              ??[4:2]

---

Zcb

+----------------+-----------------------------------------+---------------------------------------------------------------------------------------+
|   Instruction  |               Compressed                |                                    Decompressed                                       |
|                | [12] | [11:10] | [9:7]  | [6:5] | [4:2] | [31:26] | [25] | [24:20] | [19:15] | [14:12] | [11:7] | [6] | [5] | [4] | [3] | [2:0] |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+
| c.zext.b rd    | 1    | 11      | rd/rs1 | 11    | 000   | 000011  | 1    | 11111   | rd      | 111     | rd     | 0   | 0   | 1   | 0   | 011   |
| c.not rd       | 1    | 11      | rd/rs1 | 11    | 101   | 111111  | 1    | 11111   | rd      | 100     | rd     | 0   | 0   | 1   | 0   | 011   |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+

---

Zcb+Zba

+----------------+-----------------------------------------+---------------------------------------------------------------------------------------+
|   Instruction  |               Compressed                |                                    Decompressed                                       |
|                | [12] | [11:10] | [9:7]  | [6:5] | [4:2] | [31:26] | [25] | [24:20] | [19:15] | [14:12] | [11:7] | [6] | [5] | [4] | [3] | [2:0] |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+
| c.zext.w rd    | 1    | 11      | rd/rs1 | 11    | 100   | 000010  | 0    | 00000   | rd      | 000     | rd     | 0   | 1   | 1   | 1   | 011   |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+

---

Zcb+Zbb

+----------------+-----------------------------------------+---------------------------------------------------------------------------------------+
|   Instruction  |               Compressed                |                                    Decompressed                                       |
|                | [12] | [11:10] | [9:7]  | [6:5] | [4:2] | [31:26] | [25] | [24:20] | [19:15] | [14:12] | [11:7] | [6] | [5] | [4] | [3] | [2:0] |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+
| c.sext.b rd    | 1    | 11      | rd/rs1 | 11    | 001   | 011000  | 0    | 00100   | rd      | 001     | rd     | 0   | 0   | 1   | 0   | 011   |
| c.zext.h rd    | 1    | 11      | rd/rs1 | 11    | 010   | 000010  | 0    | 00000   | rd      | 100     | rd     | 0   | 1   | 1   | 0   | 011   |
| c.sext.h rd    | 1    | 11      | rd/rs1 | 11    | 011   | 011000  | 0    | 00101   | rd      | 001     | rd     | 0   | 0   | 1   | 0   | 011   |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+

---

Zcb+Zmmul

+----------------+-----------------------------------------+---------------------------------------------------------------------------------------+
|   Instruction  |               Compressed                |                                    Decompressed                                       |
|                | [12] | [11:10] | [9:7]  | [6:5] | [4:2] | [31:26] | [25] | [24:20] | [19:15] | [14:12] | [11:7] | [6] | [5] | [4] | [3] | [2:0] |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+
| c.mul rd, rs2  | 1    | 11      | rd/rs1 | 10    | rs2   | 000000  | 1    | rs2     | rd      | 000     | rd     | 0   | 1   | 1   | 0   | 011   |
+----------------+------+---------+--------+-------+-------+---------+------+---------+---------+---------+--------+-----+-----+-----+-----+-------+

---

Decompressed fixed fields

[19:15] = {01, [9:7]}
[11:7] = {01, [9:7]}
[6] = 0
[4] = 1
[2:0] = 011

---

Classification

match [11:10] {
	00 => c.srli,
	01 => c.srai,
	10 => c.andi,
	11 => match [12, 6:5] {
		000 => c.sub,
		001 => c.xor,
		010 => c.or,
		011 => c.and,
	},
}

 */

module rv_decompressor (
	input bit[31:0] in,

	output bit sigill,
	output logic is_compressed,
	output logic[31:0] out
);
	typedef enum bit[4:0] {
		OpCode_Load = 5'b00000,
		OpCode_LoadFp = 5'b00001,
		OpCode_OpImm = 5'b00100,
		OpCode_Store = 5'b01000,
		OpCode_StoreFp = 5'b01001,
		OpCode_Op = 5'b01100,
		OpCode_Lui = 5'b01101,
		OpCode_Branch = 5'b11000,
		OpCode_Jalr = 5'b11001,
		OpCode_Jal = 5'b11011,
		OpCode_System = 5'b11100
	} OpCode;

	bit out_31;
	bit out_30;
	bit out_29;
	bit out_28;
	bit out_27;
	bit out_26;
	bit out_25;
	bit out_24;
	bit out_23;
	bit out_22;
	bit out_21;
	bit out_20;
	bit[1:0] out_19_18;
	bit[2:0] out_17_15;
	bit[2:0] out_14_12;
	bit[1:0] out_11_10;
	bit out_9;
	bit out_8;
	bit out_7;
	bit[4:0] out_6_2;

	assign out = {
		out_31,
		out_30,
		out_29,
		out_28,
		out_27,
		out_26,
		out_25,
		out_24,
		out_23,
		out_22,
		out_21,
		out_20,
		out_19_18,
		out_17_15,
		out_14_12,
		out_11_10,
		out_9,
		out_8,
		out_7,
		out_6_2,
		2'b11
	};

	function automatic void type_r(bit[4:0] opcode, bit[4:0] rd, bit[2:0] funct3, bit[4:0] rs1, bit[4:0] rs2, bit[6:0] funct7);
		out_6_2 = opcode;
		{out_11_10, out_9, out_8, out_7} = rd;
		out_14_12 = funct3;
		{out_19_18, out_17_15} = rs1;
		{out_24, out_23, out_22, out_21, out_20} = rs2;
		{out_31, out_30, out_29, out_28, out_27, out_26, out_25} = funct7;
	endfunction

	function automatic void type_i(bit[4:0] opcode, bit[4:0] rd, bit[2:0] funct3, bit[4:0] rs1, bit[11:0] imm);
		out_6_2 = opcode;
		{out_11_10, out_9, out_8, out_7} = rd;
		out_14_12 = funct3;
		{out_19_18, out_17_15} = rs1;
		{out_31, out_30, out_29, out_28, out_27, out_26, out_25, out_24, out_23, out_22, out_21, out_20} = imm;
	endfunction

	function automatic void type_s(bit[4:0] opcode, bit[2:0] funct3, bit[4:0] rs1, bit[4:0] rs2, bit[11:0] imm);
		out_6_2 = opcode;
		out_14_12 = funct3;
		{out_19_18, out_17_15} = rs1;
		{out_24, out_23, out_22, out_21, out_20} = rs2;
		{out_31, out_30, out_29, out_28, out_27, out_26, out_25, out_11_10, out_9, out_8, out_7} = imm;
	endfunction

	function automatic void type_b(bit[4:0] opcode, bit[2:0] funct3, bit[4:0] rs1, bit[4:0] rs2, bit[11:0] imm);
		out_6_2 = opcode;
		out_14_12 = funct3;
		{out_19_18, out_17_15} = rs1;
		{out_24, out_23, out_22, out_21, out_20} = rs2;
		{out_31, out_7, out_30, out_29, out_28, out_27, out_26, out_25, out_11_10, out_9, out_8} = imm;
	endfunction

	function automatic void type_u(bit[4:0] opcode, bit[4:0] rd, bit[19:0] imm);
		out_6_2 = opcode;
		{out_11_10, out_9, out_8, out_7} = rd;
		{out_31, out_30, out_29, out_28, out_27, out_26, out_25, out_24, out_23, out_22, out_21, out_20, out_19_18, out_17_15, out_14_12} = imm;
	endfunction

	function automatic void type_j(bit[4:0] opcode, bit[4:0] rd, bit[19:0] imm);
		out_6_2 = opcode;
		{out_11_10, out_9, out_8, out_7} = rd;
		{out_31, out_19_18, out_17_15, out_14_12, out_20, out_30, out_29, out_28, out_27, out_26, out_25, out_24, out_23, out_22, out_21} = imm;
	endfunction

	always_comb begin
		sigill = '0;
		is_compressed = ~& in[0+:2];
		{
			out_31,
			out_30,
			out_29,
			out_28,
			out_27,
			out_26,
			out_25,
			out_24,
			out_23,
			out_22,
			out_21,
			out_20,
			out_19_18,
			out_17_15,
			out_14_12,
			out_11_10,
			out_9,
			out_8,
			out_7,
			out_6_2
		} = 'x;

		unique case (in[0+:2])
			2'b00: unique case (in[13+:3])
				3'b000: if (| in[2+:11])
					// addi4spn
					type_i(OpCode_OpImm, {2'b01, in[2+:3]}, 3'b000, 5'b00010, 12'({in[7+:4], in[11+:2], in[5], in[6], 2'b00}));
				else begin
					sigill = '1;
					is_compressed = 'x;
				end

				// fld
				3'b001: type_i(OpCode_LoadFp, {2'b01, in[2+:3]}, 3'b011, {2'b01, in[7+:3]}, 12'({in[5+:2], in[10+:3], 3'b000}));

				// lw
				3'b010: type_i(OpCode_Load, {2'b01, in[2+:3]}, 3'b010, {2'b01, in[7+:3]}, 12'({in[5], in[10+:3], in[6], 2'b00}));

				// flw
				3'b011: type_i(OpCode_LoadFp, {2'b01, in[2+:3]}, 3'b010, {2'b01, in[7+:3]}, 12'({in[5], in[10+:3], in[6], 2'b00}));

				// Zcb
				3'b100: begin
					sigill = '1;
					is_compressed = 'x;
				end

				// fsd
				3'b101: type_s(OpCode_StoreFp, 3'b011, {2'b01, in[7+:3]}, {2'b01, in[2+:3]}, 12'({in[5+:2], in[10+:3], 3'b000}));

				// sw
				3'b110: type_s(OpCode_Store, 3'b010, {2'b01, in[7+:3]}, {2'b01, in[2+:3]}, 12'({in[5], in[10+:3], in[6], 2'b00}));

				// fsw
				3'b111: type_s(OpCode_StoreFp, 3'b010, {2'b01, in[7+:3]}, {2'b01, in[2+:3]}, 12'({in[5], in[10+:3], in[6], 2'b00}));
			endcase

			2'b01: unique casez (in[13+:3])
				// addi, li
				3'b0?0: type_i(OpCode_OpImm, in[7+:5], 3'b000, {5{~in[14]}} & in[7+:5], unsigned'(12'(signed'({in[12], in[2+:5]}))));

				// jal
				3'b001: type_j(OpCode_Jal, 5'b00001, unsigned'(20'(signed'({in[12], in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3]}))));

				3'b011: if (in[7+:5] == 5'b00010)
					// addi16sp
					type_i(OpCode_OpImm, in[7+:5], 3'b000, in[7+:5], unsigned'(12'(signed'({in[12], in[3+:2], in[5], in[2], in[6], 4'b0000}))));
				else
					// lui
					type_u(OpCode_Lui, in[7+:5], unsigned'(20'(signed'({in[12], in[2+:5]}))));

				3'b100: unique casez (in[10+:2])
					// srli, srai
					2'b0?: type_i(OpCode_OpImm, {2'b01, in[7+:3]}, 3'b101, {2'b01, in[7+:3]}, {1'b0, in[10], 4'b0000, in[12], in[2+:5]});

					// andi
					2'b10: type_i(OpCode_OpImm, {2'b01, in[7+:3]}, 3'b111, {2'b01, in[7+:3]}, unsigned'(12'(signed'({in[12], in[2+:5]}))));

					2'b11: unique casez (in[12])
						// sub, xor, or, and
						1'b0: type_r(OpCode_Op, {2'b01, in[7+:3]}, {| in[5+:2], in[6], & in[5+:2]}, {2'b01, in[7+:3]}, {2'b01, in[2+:3]}, {1'b0, ~| in[5+:2], 5'b00000});

						default: begin
							sigill = '1;
							is_compressed = 'x;
						end
					endcase
				endcase

				// j
				3'b101: type_j(OpCode_Jal, 5'b00000, unsigned'(20'(signed'({in[12], in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3]}))));

				// beqz, bnez
				3'b11?: type_b(OpCode_Branch, {2'b00, in[13]}, {2'b01, in[7+:3]}, 5'b00000, unsigned'(12'(signed'({in[12], in[5+:2], in[2], in[10+:2], in[3+:2]}))));
			endcase

			2'b10: unique case (in[13+:3])
				// slli
				3'b000: type_i(OpCode_OpImm, in[7+:5], 3'b001, in[7+:5], {6'b000000, in[12], in[2+:5]});

				// fldsp
				3'b001: type_i(OpCode_LoadFp, in[7+:5], 3'b011, 5'b00010, 12'({in[2+:3], in[12], in[5+:2], 3'b000}));

				// lwsp
				3'b010: type_i(OpCode_Load, in[7+:5], 3'b010, 5'b00010, 12'({in[2+:2], in[12], in[4+:3], 2'b00}));

				// flwsp
				3'b011: type_i(OpCode_LoadFp, in[7+:5], 3'b010, 5'b00010, 12'({in[2+:2], in[12], in[4+:3], 2'b00}));

				3'b100: unique case ({| in[7+:5], | in[2+:5]})
					2'b00: if (in[12])
						// ebreak
						type_r(OpCode_System, 5'b00000, 3'b000, 5'b00000, 5'b00001, 7'b0000000);
					else begin
						sigill = '1;
						is_compressed = 'x;
					end

					// jr, jalr
					2'b10: type_i(OpCode_Jalr, {4'b0000, in[12]}, 3'b000, in[7+:5], '0);

					// mv, add
					2'b11: type_r(OpCode_Op, in[7+:5], 3'b000, {5{in[12]}} & in[7+:5], in[2+:5], 7'b0000000);

					default: begin
						sigill = '1;
						is_compressed = 'x;
					end
				endcase

				// fsdsp
				3'b101: type_s(OpCode_StoreFp, 3'b011, 5'b00010, in[2+:5], 12'({in[7+:3], in[10+:3], 3'b000}));

				// swsp
				3'b110: type_s(OpCode_Store, 3'b010, 5'b00010, in[2+:5], 12'({in[7+:2], in[9+:4], 2'b00}));

				// fswsp
				3'b111: type_s(OpCode_StoreFp, 3'b010, 5'b00010, in[2+:5], 12'({in[7+:2], in[9+:4], 2'b00}));
			endcase

			// uncompressed
			2'b11:
				{
					out_31,
					out_30,
					out_29,
					out_28,
					out_27,
					out_26,
					out_25,
					out_24,
					out_23,
					out_22,
					out_21,
					out_20,
					out_19_18,
					out_17_15,
					out_14_12,
					out_11_10,
					out_9,
					out_8,
					out_7,
					out_6_2
				} = in[2+:30];
		endcase
	end
endmodule

`ifdef TESTING
module test_rv_decompressor;
	bit[31:0] in;
	wire sigill;
	wire is_compressed;
	wire[31:0] out;
	rv_decompressor rv_decompressor_module (
		.in(in),
		.sigill(sigill), .is_compressed(is_compressed), .out(out)
	);

	task automatic test_ok(bit[31:0] in_, bit[31:0] out_);
		in = in_;
		#1
		assert(sigill == '0) else $fatal;
		assert(is_compressed == '1) else $fatal;
		assert(out == out_) else $fatal;
	endtask

	task automatic test_err(bit[31:0] in_);
		in = in_;
		#1
		assert(sigill == '1) else $fatal;
	endtask

	initial begin
		// All zeros
		test_err(32'b0);

		// addi4spn
		test_ok(32'b000_01010101_010_00, 32'b000101011000_00010_000_01010_00100_11);

		// fld
		test_ok(32'b001_010_010_01_010_00, 32'b000001010000_01010_011_01010_00001_11);

		// lw
		test_ok(32'b010_010_010_01_010_00, 32'b000001010000_01010_010_01010_00000_11);

		// flw
		test_ok(32'b011_010_010_01_010_00, 32'b000001010000_01010_010_01010_00001_11);

		// Zcb
		test_err(32'b100_00000000000_00);

		// fsd
		test_ok(32'b101_010_010_01_010_00, 32'b0000010_01010_01010_011_10000_01001_11);

		// sw
		test_ok(32'b110_010_010_01_010_00, 32'b0000010_01010_01010_010_10000_01000_11);

		// fsw
		test_ok(32'b111_010_010_01_010_00, 32'b0000010_01010_01010_010_10000_01001_11);

		// addi
		test_ok(32'b000_1_01010_01010_01, 32'b111111101010_01010_000_01010_00100_11);

		// jal
		test_ok(32'b001_01010101010_01, 32'b00010101101000000000_00001_11011_11);

		// li
		test_ok(32'b010_1_01010_01010_01, 32'b111111101010_00000_000_01010_00100_11);

		// addi16sp
		test_ok(32'b011_1_00010_01010_01, 32'b111011000000_00010_000_00010_00100_11);

		// lui
		test_ok(32'b011_1_01010_01010_01, 32'b11111111111111101010_01010_01101_11);

		// srli
		test_ok(32'b100_1_00_010_01010_01, 32'b000000101010_01010_101_01010_00100_11);

		// srai
		test_ok(32'b100_1_01_010_01010_01, 32'b010000101010_01010_101_01010_00100_11);

		// andi
		test_ok(32'b100_1_10_010_01010_01, 32'b111111101010_01010_111_01010_00100_11);

		// sub
		test_ok(32'b100_011_010_00_010_01, 32'b0100000_01010_01010_000_01010_01100_11);

		// xor
		test_ok(32'b100_011_010_01_010_01, 32'b0000000_01010_01010_100_01010_01100_11);

		// or
		test_ok(32'b100_011_010_10_010_01, 32'b0000000_01010_01010_110_01010_01100_11);

		// and
		test_ok(32'b100_011_010_11_010_01, 32'b0000000_01010_01010_111_01010_01100_11);

		// subw
		test_err(32'b100_111_010_00_010_01);

		// addw
		test_err(32'b100_111_010_01_010_01);

		// Reserved
		test_err(32'b100_111_010_10_010_01);

		// Reserved
		test_err(32'b100_111_010_11_010_01);

		// j
		test_ok(32'b101_01010101010_01, 32'b00010101101000000000_00000_11011_11);

		// beqz
		test_ok(32'b110_101_010_01010_01, 32'b1111010_00000_01010_000_01011_11000_11);

		// bnez
		test_ok(32'b111_101_010_01010_01, 32'b1111010_00000_01010_001_01011_11000_11);

		// slli
		test_ok(32'b000_1_01010_01010_10, 32'b00000101010_01010_001_01010_00100_11);

		// fldsp
		test_ok(32'b001_1_01010_01010_10, 32'b000010101000_00010_011_01010_00001_11);

		// lwsp
		test_ok(32'b010_1_01010_01010_10, 32'b000010101000_00010_010_01010_00000_11);

		// flwsp
		test_ok(32'b011_1_01010_01010_10, 32'b000010101000_00010_010_01010_00001_11);

		// jr
		test_ok(32'b100_0_01010_00000_10, 32'b000000000000_01010_000_00000_11001_11);

		// mv
		test_ok(32'b100_0_01010_01010_10, 32'b0000000_01010_00000_000_01010_01100_11);

		// ebreak
		test_ok(32'b100_1_00000_00000_10, 32'b000000000001_00000_000_00000_11100_11);

		// jalr
		test_ok(32'b100_1_01010_00000_10, 32'b000000000000_01010_000_00001_11001_11);

		// add
		test_ok(32'b100_1_01010_01010_10, 32'b0000000_01010_01010_000_01010_01100_11);

		// fsdsp
		test_ok(32'b101_101010_01010_10, 32'b0000101_01010_00010_011_01000_01001_11);

		// swsp
		test_ok(32'b110_101010_01010_10, 32'b0000101_01010_00010_010_01000_01000_11);

		// fswsp
		test_ok(32'b111_101010_01010_10, 32'b0000101_01010_00010_010_01000_01001_11);

		// uncompressed
		begin
			in = 32'b000000000000_00000_000_00000_00100_11;
			#1
			assert(sigill == '0) else $fatal;
			assert(is_compressed == '0) else $fatal;
			assert(out == 32'b000000000000_00000_000_00000_00100_11) else $fatal;
		end
	end
endmodule
`endif
