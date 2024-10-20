/*

Refs:

- https://arxiv.org/pdf/1607.02318

- https://en.wikichip.org/wiki/macro-operation_fusion#RISC-V

- https://github.com/llvm/llvm-project/blob/173907b5d77115623f160978a95159e36e05ee6c/llvm/lib/Target/RISCV/RISCVMacroFusion.td

---

Load immediate

+---------------------------+-------------------------------------------------+-------------------------------+
|       Instructions        |                Fusion condition                 |       Fused instruction       |
+===========================+=================================================+===============================+
| auipc rd_a, imm_a         | rd_a == rd_b && rd_a == rs1_b                   | auipc rd_a, (imm_a + imm_b)   |
| addi rd_b, rs1_b, imm_b   |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b && rs1_b != rs2_b | addi rd_a, rs2_b, imm_a       |
| add rd_b, rs1_b, rs2_b    |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b && rs1_b != rs2_b | addiw rd_a, rs2_b, imm_a      |
| addw rd_b, rs1_b, rs2_b   |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b                   | lui rd_a, (imm_a + imm_b)     |
| addi rd_b, rs1_b, imm_b   |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b                   | lui rd_a, 32'(imm_a + imm_b)  |
| addiw rd_b, rs1_b, imm_b  |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+

Jump

+---------------------------+-------------------------------------------------+-------------------------------+
|       Instructions        |                Fusion condition                 |       Fused instruction       |
+===========================+=================================================+===============================+
| auipc rd_a, imm_a         | rd_a == rd_b && rd_a == rs1_b                   | jal rd_a, (imm_a + imm_b)     |
| jalr rd_b, imm_b(rs1_b)   |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+

Load

+---------------------------+-------------------------------------------------+-------------------------------+
|       Instructions        |                Fusion condition                 |       Fused instruction       |
+===========================+=================================================+===============================+
| auipc rd_a, imm_a         | rd_a == rd_b && rd_a == rs1_b                   | ld.pc rd_a, (imm_a + imm_b)pc |
| ld rd_b, imm_b(rs1_b)     |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b                   | ld rd_a, (imm_a + imm_b)x0    |
| ld rd_b, imm_b(rs1_b)     |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| add rd_a, rs1_a, rs2_a    | rd_a == rd_b && rd_a == rs1_b && imm_b == 0     | ld.add rd_a, (rs1_a)(rs2_a)   |
| ld rd_b, imm_b(rs1_b)     |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+
| sh1add rd_a, rs1_a, rs2_a | rd_a == rd_b && rd_a == rs1_b && imm_b == 0     | ld.sh1add rd_a, rs1_a, rs2_a  |
| ld rd_b, imm_b(rs1_b)     |                                                 |                               |
+---------------------------+-------------------------------------------------+-------------------------------+

---

Fused instruction length

+------+-------+-------+------+------+------+
| fuse | RVC_2 | RVC_1 | len2 | len4 | len8 |
+======+=======+=======+======+======+======+
| 0    | 0     | 0     | 0    | 1    | 0    |
| 0    | 0     | 1     | 1    | 0    | 0    |
| 0    | 1     | 0     | 0    | 1    | 0    |
| 0    | 1     | 1     | 1    | 0    | 0    |
| 1    | 0     | 0     | 0    | 0    | 1    |
| 1    | 0     | 1     | 1    | 1    | 0    |
| 1    | 1     | 0     | 1    | 1    | 0    |
| 1    | 1     | 1     | 0    | 1    | 0    |
+------+-------+-------+------+------+------+

 */

module rv_mop_fusion (
	input bit a_is_compressed,
	input logic[4:0] a_rd,
	input logic[4:0] a_rs1,
	input logic[4:0] a_rs2,
	input logic[11:0] a_csr,
	input bit[4:0] a_opcode,
	input logic[2:0] a_funct3,
	input logic[6:0] a_funct7,
	input logic[4:0] a_funct5,
	input logic[31:0] a_imm,
	input logic[4:0] a_csrimm,

	input bit b_is_valid,
	input bit b_is_compressed,
	input logic[4:0] b_rd,
	input logic[4:0] b_rs1,
	input logic[4:0] b_rs2,
	input bit[4:0] b_opcode,
	input logic[2:0] b_funct3,
	input logic[6:0] b_funct7,
	input logic[31:0] b_imm,

	output bit insts_num_minus_one,
	output bit[1:0] insts_len_half_minus_one,

	output logic[4:0] rd,
	output logic[4:0] rs1,
	output logic[4:0] rs2,
	output logic[11:0] csr,
	output bit[4:0] opcode,
	output logic[2:0] funct3,
	output logic[6:0] funct7,
	output logic[4:0] funct5,
	output logic[32:0] imm,
	output logic[4:0] csrimm
);
	typedef enum bit[4:0] {
		OpCode_Load = 5'b00000,
		OpCode_Zarnavion = 5'b00010,
		OpCode_OpImm = 5'b00100,
		OpCode_Auipc = 5'b00101,
		OpCode_OpImm32 = 5'b00110,
		OpCode_Op = 5'b01100,
		OpCode_Lui = 5'b01101,
		OpCode_Op32 = 5'b01110,
		OpCode_Jalr = 5'b11001,
		OpCode_Jal = 5'b11011
	} OpCode;

	wire imm_a_plus_b_cout;
	wire[31:0] imm_a_plus_b_lo;
	assign {imm_a_plus_b_cout, imm_a_plus_b_lo} = 33'(a_imm) + 33'(b_imm);
	wire[32:0] imm_a_plus_b = {a_imm[31] ^ b_imm[31] ^ imm_a_plus_b_cout, imm_a_plus_b_lo};

	bit performed_fusion;

	always_comb begin
		performed_fusion = '0;

		rd = a_rd;
		rs1 = a_rs1;
		rs2 = a_rs2;
		csr = a_csr;
		opcode = a_opcode;
		funct3 = a_funct3;
		funct7 = a_funct7;
		funct5 = a_funct5;
		imm = unsigned'(33'(signed'(a_imm)));
		csrimm = a_csrimm;

		if (b_is_valid && a_rd == b_rd && a_rd == b_rs1)
			unique casez ({a_opcode, a_funct3, a_funct7, b_opcode, b_funct3, b_funct7})
				// auipc, addi -> auipc
				{OpCode_Auipc, 10'b???_???????, OpCode_OpImm, 10'b000_???????}: begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1; // = '0
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = a_opcode;
					funct3 = 'x;
					funct7 = 'x;
					funct5 = 'x;
					imm = imm_a_plus_b;
					csrimm = 'x;
				end

				// lui, add -> addi
				{OpCode_Lui, 10'b???_???????, OpCode_Op, 10'b000_0000000}: if (b_rs1 == b_rs2) begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = b_rs2;
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = OpCode_OpImm;
					funct3 = b_funct3;
					funct7 = 'x;
					funct5 = 'x;
					imm = {a_imm[31], a_imm};
					csrimm = 'x;
				end

				// lui, addw -> addiw
				{OpCode_Lui, 10'b???_???????, OpCode_Op32, 10'b000_0000000}: if (b_rs1 == b_rs2) begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = b_rs2;
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = OpCode_OpImm32;
					funct3 = b_funct3;
					funct7 = 'x;
					funct5 = 'x;
					imm = {a_imm[31], a_imm};
					csrimm = 'x;
				end

				// lui, addi -> lui
				{OpCode_Lui, 10'b???_???????, OpCode_OpImm, 10'b000_???????}: begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1; // = '0
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = a_opcode;
					funct3 = 'x;
					funct7 = 'x;
					funct5 = 'x;
					imm = imm_a_plus_b;
					csrimm = 'x;
				end

				// lui, addiw -> lui
				{OpCode_Lui, 10'b???_???????, OpCode_OpImm32, 10'b000_???????}: begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1; // = '0
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = a_opcode;
					funct3 = 'x;
					funct7 = 'x;
					funct5 = 'x;
					imm = unsigned'(33'(signed'(imm_a_plus_b[0+:32])));
					csrimm = 'x;
				end

				// auipc, jalr -> jal
				{OpCode_Auipc, 10'b???_???????, OpCode_Jalr, 10'b???_???????}: begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1; // = '0
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = OpCode_Jal;
					funct3 = 'x;
					funct7 = 'x;
					funct5 = 'x;
					imm = imm_a_plus_b;
					csrimm = 'x;
				end

				// auipc, load -> load.pc
				{OpCode_Auipc, 10'b???_???????, OpCode_Load, 10'b???_???????}: begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1; // = '0
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = OpCode_Zarnavion;
					funct3 = b_funct3;
					funct7 = 7'b0000000;
					funct5 = 'x;
					imm = imm_a_plus_b;
					csrimm = 'x;
				end

				// lui, load -> load
				{OpCode_Lui, 10'b???_???????, OpCode_Load, 10'b???_???????}: begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = 5'b00000;
					rs2 = a_rs2; // = '0
					csr = a_csr; // = 'x
					opcode = b_opcode;
					funct3 = b_funct3;
					funct7 = 'x;
					funct5 = 'x;
					imm = imm_a_plus_b;
					csrimm = 'x;
				end

				// add, load -> load.add
				{OpCode_Op, 10'b000_0000000, OpCode_Load, 10'b???_???????}: if (b_imm == '0) begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1;
					rs2 = a_rs2;
					csr = a_csr; // = 'x
					opcode = OpCode_Zarnavion;
					funct3 = b_funct3;
					funct7 = 7'b0000001;
					funct5 = 'x;
					imm = 'x;
					csrimm = 'x;
				end

				// sh1add, load -> load.sh1add
				{OpCode_Op, 10'b010_0010000, OpCode_Load, 10'b???_???????}: if (b_imm == '0) begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1;
					rs2 = a_rs2;
					csr = a_csr; // = 'x
					opcode = OpCode_Zarnavion;
					funct3 = b_funct3;
					funct7 = 7'b0000010;
					funct5 = 'x;
					imm = 'x;
					csrimm = 'x;
				end

				// sh2add, load -> load.sh2add
				{OpCode_Op, 10'b100_0010000, OpCode_Load, 10'b???_???????}: if (b_imm == '0) begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1;
					rs2 = a_rs2;
					csr = a_csr; // = 'x
					opcode = OpCode_Zarnavion;
					funct3 = b_funct3;
					funct7 = 7'b0000011;
					funct5 = 'x;
					imm = 'x;
					csrimm = 'x;
				end

				// sh3add, load -> load.sh3add
				{OpCode_Op, 10'b110_0010000, OpCode_Load, 10'b???_???????}: if (b_imm == '0) begin
					performed_fusion = '1;

					rd = a_rd;
					rs1 = a_rs1;
					rs2 = a_rs2;
					csr = a_csr; // = 'x
					opcode = OpCode_Zarnavion;
					funct3 = b_funct3;
					funct7 = 7'b0000100;
					funct5 = 'x;
					imm = 'x;
					csrimm = 'x;
				end

				default: ;
			endcase

		// insts_num_minus_one = performed_fusion ? 1'b1 : 1'b0;
		insts_num_minus_one = performed_fusion;

		unique casez ({performed_fusion, a_is_compressed, b_is_compressed})
			3'b00?: insts_len_half_minus_one = 2'b01; // 4 = 2 * (1 + 1)
			3'b01?: insts_len_half_minus_one = 2'b00; // 2 = 2 * (1 + 0)
			3'b100: insts_len_half_minus_one = 2'b11; // 8 = 2 * (1 + 3)
			3'b101: insts_len_half_minus_one = 2'b10; // 6 = 2 * (1 + 2)
			3'b110: insts_len_half_minus_one = 2'b10; // 6 = 2 * (1 + 2)
			3'b111: insts_len_half_minus_one = 2'b01; // 4 = 2 * (1 + 1)
		endcase
	end
endmodule
