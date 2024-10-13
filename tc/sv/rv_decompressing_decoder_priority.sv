module rv_decompressing_decoder_priority #(
	parameter rv64 = 1
) (
	input bit[31:0] in,

	output bit sigill,
	output logic is_compressed,
	output logic[4:0] rd,
	output logic[4:0] rs1,
	output logic[4:0] rs2,
	output logic[11:0] csr,
	output logic csr_load,
	output logic csr_store,
	output bit[4:0] opcode,
	output bit[2:0] funct3,
	output bit[6:0] funct7,
	output bit[4:0] funct5,
	output logic[31:0] imm,
	output logic[4:0] csrimm
);
	typedef enum bit[4:0] {
		OpCode_Load = 5'b00000,
		OpCode_OpImm = 5'b00100,
		OpCode_OpImm32 = 5'b00110,
		OpCode_Store = 5'b01000,
		OpCode_Op = 5'b01100,
		OpCode_Lui = 5'b01101,
		OpCode_Op32 = 5'b01110,
		OpCode_Branch = 5'b11000,
		OpCode_Jalr = 5'b11001,
		OpCode_Jal = 5'b11011,
		OpCode_System = 5'b11100
	} OpCode;

	bit[1:0] rd_4_3;
	bit[2:0] rd_2_0;
	assign rd = {rd_4_3, rd_2_0};
	function automatic void rd_(bit[4:0] rd);
		{rd_4_3, rd_2_0} = rd;
	endfunction

	bit[1:0] rs1_4_3;
	bit[2:0] rs1_2_0;
	assign rs1 = {rs1_4_3, rs1_2_0};
	function automatic void rs1_(bit[4:0] rs1);
		{rs1_4_3, rs1_2_0} = rs1;
	endfunction

	bit[1:0] rs2_4_3;
	bit[2:0] rs2_2_0;
	assign rs2 = {rs2_4_3, rs2_2_0};
	function automatic void rs2_(bit[4:0] rs2);
		{rs2_4_3, rs2_2_0} = rs2;
	endfunction

	bit[11:0] imm_31_20;
	bit[1:0] imm_19_18;
	bit imm_17;
	bit[4:0] imm_16_12;
	bit imm_11;
	bit imm_10;
	bit imm_9;
	bit imm_8;
	bit imm_7;
	bit imm_6;
	bit imm_5;
	bit imm_4;
	bit imm_3;
	bit imm_2;
	bit imm_1;
	bit imm_0;
	assign imm = {imm_31_20, imm_19_18, imm_17, imm_16_12, imm_11, imm_10, imm_9, imm_8, imm_7, imm_6, imm_5, imm_4, imm_3, imm_2, imm_1, imm_0};
	function automatic void imm_(bit[31:0] imm);
		{imm_31_20, imm_19_18, imm_17, imm_16_12, imm_11, imm_10, imm_9, imm_8, imm_7, imm_6, imm_5, imm_4, imm_3, imm_2, imm_1, imm_0} = imm;
	endfunction

	always_comb begin
		sigill = '0;
		is_compressed = ~& in[0+:2];

		rd_('x);
		rs1_('x);
		rs2_('x);
		csr = 'x;
		csr_load = 'x;
		csr_store = 'x;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		imm_('x);
		csrimm = 'x;

		priority casez (in[0+:16])
			16'b0000000000000000: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// addi4spn
			16'b000_????????_???_00: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b000;

				rd_({2'b01, in[2+:3]});
				rs1_(5'b00010);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[7+:4], in[11+:2], in[5], in[6], 2'b0}));
			end

			// fld
			16'b001_???_???_??_???_00: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// lw
			16'b010_???_???_??_???_00: begin
				opcode = OpCode_Load;
				funct3 = 3'b010;

				rd_({2'b01, in[2+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[5], in[10+:3], in[6], 2'b0}));
			end

			16'b011_???_???_??_???_00: if (rv64) begin
				// ld
				opcode = OpCode_Load;
				funct3 = 3'b011;

				rd_({2'b01, in[2+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[5+:2], in[10+:3], 3'b0}));
			end else begin
				// flw
				sigill = '1;
				is_compressed = 'x;
			end

			// lbu, lhu, lh
			16'b100_00?_???_??_???_00: begin
				opcode = OpCode_Load;
				funct3 = {~in[10] | ~in[6], 1'b0, in[10]};

				rd_({2'b01, in[2+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[5], ~in[10] & in[6]}));
			end

			// sb, sh
			16'b100_01?_???_??_???_00: begin
				opcode = OpCode_Store;
				funct3 = {2'b00, in[10]};

				rd_(5'b00000);
				rs1_({2'b01, in[7+:3]});
				rs2_({2'b01, in[2+:3]});
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[5], ~in[10] & in[6]}));
			end

			16'b100_???_???_??_???_00: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// fsd
			16'b101_???_???_??_???_00: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// sw
			16'b110_???_???_??_???_00: begin
				opcode = OpCode_Store;
				funct3 = 3'b010;

				rd_(5'b00000);
				rs1_({2'b01, in[7+:3]});
				rs2_({2'b01, in[2+:3]});
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[5], in[10+:3], in[6], 2'b0}));
			end

			16'b111_???_???_??_???_00: if (rv64) begin
				// sd
				opcode = OpCode_Store;
				funct3 = 3'b011;

				rd_(5'b00000);
				rs1_({2'b01, in[7+:3]});
				rs2_({2'b01, in[2+:3]});
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[5+:2], in[10+:3], 3'b0}));
			end else begin
				// fsw
				sigill = '1;
				is_compressed = 'x;
			end

			// addi, li
			16'b0?0_?_?????_?????_01: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b000;

				rd_(in[7+:5]);
				rs1_({5{~in[14]}} & in[7+:5]);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[2+:5]}))));
			end

			16'b001_?_?????_?????_01: if (rv64) begin
				// addiw
				opcode = OpCode_OpImm32;
				funct3 = 3'b000;

				rd_(in[7+:5]);
				rs1_(in[7+:5]);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[2+:5]}))));
			end else begin
				// jal
				opcode = OpCode_Jal;

				rd_(5'b00001);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0}))));
			end

			// addi16sp
			16'b011_?_00010_?????_01: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b000;

				rd_(5'b00010);
				rs1_(5'b00010);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[3+:2], in[5], in[2], in[6], 4'b0}))));
			end

			// lui
			16'b011_?_?????_?????_01: begin
				opcode = OpCode_Lui;

				rd_(in[7+:5]);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[2+:5], 12'b0}))));
			end

			// srli, srai
			16'b100_?_0?_???_?????_01: if (!rv64 && in[12]) begin
				opcode = OpCode_OpImm;
				funct3 = 3'b101;
				funct7 = {1'b0, in[10], 4'b0000, in[12]};

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[10], 4'b0000, in[12], in[2+:5]}));
			end else begin
				sigill = '1;
				is_compressed = 'x;
			end

			// andi
			16'b100_?_10_???_?????_01: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b111;

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[2+:5]}))));
			end

			// sub, xor, or, and
			16'b100_0_11_???_??_???_01: begin
				opcode = OpCode_Op;
				funct3 = {| in[5+:2], in[6], & in[5+:2]};
				funct7 = {1'b0, ~| in[5+:2], 5'b00000};

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_({2'b01, in[2+:3]});
				csr_load = '0;
				csr_store = '0;
			end

			16'b100_1_11_???_0?_???_01: if (rv64) begin
				// subw, addw
				opcode = OpCode_Op32;
				funct3 = 3'b000;
				funct7 = {1'b0, ~in[5], 5'b00000};

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_({2'b01, in[2+:3]});
				csr_load = '0;
				csr_store = '0;
			end else begin
				sigill = '1;
				is_compressed = 'x;
			end

			// zext.b
			16'b100_1_11_???_11_000_01: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b111;

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'(8'('1)));
			end

			16'b100_1_11_???_11_100_01: if (rv64) begin
				// zext.w
				opcode = OpCode_Op32;
				funct3 = 3'b000;
				funct7 = 7'b0000100;

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;
			end else begin
				sigill = '1;
				is_compressed = 'x;
			end

			// not
			16'b100_1_11_???_11_101_01: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b100;

				rd_({2'b01, in[7+:3]});
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'('1));
			end

			16'b100_1_11_???_??_???_01: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// j
			16'b101_???????????_01: begin
				opcode = OpCode_Jal;

				rd_(5'b00000);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0}))));
			end

			// beqz, bnez
			16'b11?_???_???_?????_01: begin
				opcode = OpCode_Branch;
				funct3 = {2'b00, in[13]};

				rd_(5'b00000);
				rs1_({2'b01, in[7+:3]});
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[12], in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0}))));
			end

			// slli
			16'b000_0_?????_?????_10: begin
				opcode = OpCode_OpImm;
				funct3 = 3'b001;

				rd_(in[7+:5]);
				rs1_(in[7+:5]);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[12], in[2+:5]}));
			end

			// slli
			16'b000_1_?????_?????_10: if (rv64) begin
				opcode = OpCode_OpImm;
				funct3 = 3'b001;

				rd_(in[7+:5]);
				rs1_(in[7+:5]);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[12], in[2+:5]}));
			end else begin
				sigill = '1;
				is_compressed = 'x;
			end

			// fldsp
			16'b001_?_?????_?????_10: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// lwsp
			16'b010_?_?????_?????_10: begin
				opcode = OpCode_Load;
				funct3 = 3'b010;

				rd_(in[7+:5]);
				rs1_(5'b00010);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[2+:2], in[12], in[4+:3], 2'b0}));
			end

			16'b011_?_?????_?????_10: if (rv64) begin
				// ldsp
				opcode = OpCode_Load;
				funct3 = 3'b011;

				rd_(in[7+:5]);
				rs1_(5'b00010);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[2+:3], in[12], in[5+:2], 3'b0}));
			end else begin
				// flwsp
				sigill = '1;
				is_compressed = 'x;
			end

			// ebreak
			16'b100_1_00000_00000_10: begin
				opcode = OpCode_System;
				funct3 = 3'b000;
				funct7 = 7'b0000000;
				funct5 = 5'b00001;

				rd_(5'b00000);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;
			end

			16'b100_?_00000_?????_10: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// jr, jalr
			16'b100_?_?????_00000_10: begin
				opcode = OpCode_Jalr;
				funct3 = 3'b000;

				rd_({4'b0000, in[12]});
				rs1_(in[15+:5]);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_('0);
			end

			// mv, add
			16'b100_?_?????_?????_10: begin
				opcode = OpCode_Op;
				funct3 = 3'b000;
				funct7 = 7'b0000000;

				rd_(in[7+:5]);
				rs1_({5{in[12]}} & in[15+:5]);
				rs2_(in[2+:5]);
				csr_load = '0;
				csr_store = '0;
			end

			// fsdsp
			16'b101_??????_?????_10: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// swsp
			16'b110_??????_?????_10: begin
				opcode = OpCode_Store;
				funct3 = 3'b010;

				rd_(5'b00000);
				rs1_(5'b00010);
				rs2_(in[2+:5]);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[7+:2], in[9+:4], 2'b0}));
			end

			16'b111_??????_?????_10: if (rv64) begin
				// sdsp
				opcode = OpCode_Store;
				funct3 = 3'b011;

				rd_(5'b00000);
				rs1_(5'b00010);
				rs2_(in[2+:5]);
				csr_load = '0;
				csr_store = '0;

				imm_(32'({in[7+:3], in[10+:3], 3'b0}));
			end else begin
				// fswsp
				sigill = '1;
				is_compressed = 'x;
			end

			// op, op-32
			16'b?_???_?????_011?0_11: begin
				opcode = in[2+:5];
				funct3 = in[12+:3];
				funct7 = in[25+:7];
				funct5 = in[20+:5];

				rd_(in[7+:5]);
				rs1_(in[15+:5]);
				rs2_(in[20+:5]);
				csr_load = '0;
				csr_store = '0;
			end

			// load
			16'b?_???_?????_00000_11,
			// misc-mem
			16'b?_???_?????_00011_11,
			// op-imm, op-imm-32
			16'b?_???_?????_001?0_11,
			// jalr
			16'b?_???_?????_11001_11: begin
				opcode = in[2+:5];
				funct3 = in[12+:3];

				rd_(in[7+:5]);
				rs1_(in[15+:5]);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'(in[20+:12]))));
			end

			// store
			16'b?_???_?????_01000_11: begin
				opcode = in[2+:5];
				funct3 = in[12+:3];

				rd_(5'b00000);
				rs1_(in[15+:5]);
				rs2_(in[20+:5]);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[25+:7], in[7+:5]}))));
			end

			// branch
			16'b?_???_?????_11000_11: begin
				opcode = in[2+:5];
				funct3 = in[12+:3];

				rd_(5'b00000);
				rs1_(in[15+:5]);
				rs2_(in[20+:5]);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[31], in[7], in[25+:6], in[8+:4], 1'b0}))));
			end

			// auipc, lui
			16'b?_???_?????_0?101_11: begin
				opcode = in[2+:5];

				rd_(in[7+:5]);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_({in[12+:20], 12'b0});
			end

			// jal
			16'b?_???_?????_11011_11: begin
				opcode = in[2+:5];

				rd_(in[7+:5]);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;

				imm_(unsigned'(32'(signed'({in[31], in[12+:8], in[20], in[21+:10], 1'b0}))));
			end

			// ebreak, ecall
			16'b?_000_?????_11100_11: begin
				opcode = in[2+:5];
				funct3 = in[12+:3];
				funct7 = in[25+:7];
				funct5 = in[20+:5];

				rd_(5'b00000);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr_load = '0;
				csr_store = '0;
			end

			// csrrw
			16'b?_001_?????_11100_11: begin
				rd_(in[7+:5]);
				rs1_(in[15+:5]);
				rs2_(5'b00000);
				csr = in[20+:12];
				csr_load = | in[7+:5];
				csr_store = '1;
			end

			// csrrs
			16'b?_010_?????_11100_11: begin
				rd_(in[7+:5]);
				rs1_(in[15+:5]);
				rs2_(5'b00000);
				csr = in[20+:12];
				csr_load = '1;
				csr_store = | in[15+:5];
			end

			// csrrc
			16'b?_011_?????_11100_11: begin
				rd_(in[7+:5]);
				rs1_(in[15+:5]);
				rs2_(5'b00000);
				csr = in[20+:12];
				csr_load = '1;
				csr_store = | in[15+:5];
			end

			// csrrwi
			16'b?_101_?????_11100_11: begin
				rd_(in[7+:5]);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr = in[20+:12];
				csrimm = in[15+:5];
				csr_load = | in[7+:5];
				csr_store = '1;
			end

			// csrrsi
			16'b?_110_?????_11100_11: begin
				rd_(in[7+:5]);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr = in[20+:12];
				csrimm = in[15+:5];
				csr_load = '1;
				csr_store = | in[15+:5];
			end

			// csrrci
			16'b?_111_?????_11100_11: begin
				rd_(in[7+:5]);
				rs1_(5'b00000);
				rs2_(5'b00000);
				csr = in[20+:12];
				csrimm = in[15+:5];
				csr_load = '1;
				csr_store = | in[15+:5];
			end

			16'b?_???_?????_?????_11: begin
				sigill = '1;
				is_compressed = 'x;
			end
		endcase
	end
endmodule
