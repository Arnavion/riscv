/*

Refs:

- https://arxiv.org/pdf/1607.02318

- https://en.wikichip.org/wiki/macro-operation_fusion#RISC-V

- https://github.com/llvm/llvm-project/blob/173907b5d77115623f160978a95159e36e05ee6c/llvm/lib/Target/RISCV/RISCVMacroFusion.td

---

Load immediate

+---------------------------+-------------------------------------------------+--------------------------------------+
|       Instructions        |                Fusion condition                 |          Fused instruction           |
+===========================+=================================================+======================================+
| auipc rd_a, imm_a         | rd_a == rd_b && rd_a == rs1_b                   | addi rd_a, x0, (imm_a + imm_b)       |
| addi rd_b, rs1_b, imm_b   |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b && rs1_b != rs2_b | addi rd_a, rs2_b, imm_a              |
| add rd_b, rs1_b, rs2_b    |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b                   | addi rd_a, x0, (imm_a + imm_b)       |
| addi rd_b, rs1_b, imm_b   |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b                   | addiw rd_a, x0, (imm_a + imm_b)      |
| addiw rd_b, rs1_b, imm_b  |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+

Jump

+---------------------------+-------------------------------------------------+--------------------------------------+
|       Instructions        |                Fusion condition                 |          Fused instruction           |
+===========================+=================================================+======================================+
| auipc rd_a, imm_a         | rd_a == rd_b && rd_a == rs1_b                   | jal rd_a, (imm_a + imm_b)            |
| jalr rd_b, imm_b(rs1_b)   |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+

Load

+---------------------------+-------------------------------------------------+--------------------------------------+
|       Instructions        |                Fusion condition                 |          Fused instruction           |
+===========================+=================================================+======================================+
| auipc rd_a, imm_a         | rd_a == rd_b && rd_a == rs1_b                   | ld.pc rd_a, (imm_a + imm_b)pc        |
| ld rd_b, imm_b(rs1_b)     |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+
| lui rd_a, imm_a           | rd_a == rd_b && rd_a == rs1_b                   | ld rd_a, (imm_a + imm_b)x0           |
| ld rd_b, imm_b(rs1_b)     |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+
| add rd_a, rs1_a, rs2_a    | rd_a == rd_b && rd_a == rs1_b && imm_b == 0     | ld.add rd_a, (rs1_a)(rs2_a)          |
| ld rd_b, imm_b(rs1_b)     |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+
| sh1add rd_a, rs1_a, rs2_a | rd_a == rd_b && rd_a == rs1_b && imm_b == 0     | ld.sh1add rd_a, rs1_a, rs2_a         |
| ld rd_b, imm_b(rs1_b)     |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+

Op

+---------------------------+-------------------------------------------------+--------------------------------------+
|       Instructions        |                Fusion condition                 |          Fused instruction           |
+===========================+=================================================+======================================+
| sub rd_a, x0, rs2_a       | rd_a == rd_b && rd_a == rs1_b && rs2_a == rs2_b | abs rd_a, rs2_a                      |
| max rd_b, rs1_b, rs2_b    |                                                 |                                      |
+---------------------------+-------------------------------------------------+--------------------------------------+

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

module mop_fusion (
	input bit a_is_compressed,
	input logic[31:0] a_rd_decoded,
	input logic[31:0] a_rs1_decoded,
	input logic[31:0] a_rs2_decoded,
	input logic[11:0] a_csr,
	input bit[4:0] a_opcode,
	input logic[2:0] a_funct3,
	input logic[6:0] a_funct7,
	input logic[4:0] a_funct5,
	input logic[31:0] a_imm,
	input logic[4:0] a_csrimm,

	input bit b_is_compressed,
	input logic[31:0] b_rd_decoded,
	input logic[31:0] b_rs1_decoded,
	input logic[31:0] b_rs2_decoded,
	input bit[4:0] b_opcode,
	input logic[2:0] b_funct3,
	input logic[31:0] b_imm,

	output bit[1:0] insts_num,
	output bit[3:0] insts_len,

	output logic[31:0] rd_decoded,
	output logic[31:0] rs1_decoded,
	output logic[31:0] rs2_decoded,
	output logic[11:0] csr,
	output bit[4:0] opcode,
	output logic[2:0] funct3,
	output logic[6:0] funct7,
	output logic[4:0] funct5,
	output logic[31:0] imm,
	output logic[4:0] csrimm
);
	wire rd_a_eq_b = (a_rd_decoded & b_rd_decoded) != '0;
	wire rd_a_eq_rs1_b = (b_rd_decoded & b_rs1_decoded) != '0;
	wire rs1_b_ne_rs2_b = (b_rs1_decoded & b_rs2_decoded) == '0;
	wire imm_b_eq_0 = b_imm == '0;

	wire[31:0] imm_a_plus_b = a_imm + b_imm;

	bit performed_fusion;

	always_comb begin
		unique casez ({a_opcode, a_funct3, a_funct7, b_opcode, b_funct3, rd_a_eq_b, rd_a_eq_rs1_b, rs1_b_ne_rs2_b, imm_b_eq_0})
			// auipc, addi
			27'b00101_???_???????_00100_000_1_1_?_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = b_opcode;
				funct3 = b_funct3;
				funct7 = 'x;
				funct5 = 'x;
				imm = imm_a_plus_b;
				csrimm = 'x;
			end

			// lui, add
			27'b01101_???_???????_01100_000_1_1_1_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = b_rs2_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b00100;
				funct3 = b_funct3;
				funct7 = 'x;
				funct5 = 'x;
				imm = a_imm;
				csrimm = 'x;
			end

			// lui, addi
			27'b01101_???_???????_00100_000_1_1_?_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = b_opcode;
				funct3 = b_funct3;
				funct7 = 'x;
				funct5 = 'x;
				imm = imm_a_plus_b;
				csrimm = 'x;
			end

			// lui, addiw
			27'b01101_???_???????_00110_000_1_1_?_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = b_opcode;
				funct3 = b_funct3;
				funct7 = 'x;
				funct5 = 'x;
				imm = imm_a_plus_b;
				csrimm = 'x;
			end

			// auipc, jalr
			27'b00101_???_???????_11001_???_1_1_?_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b11011;
				funct3 = 'x;
				funct7 = 'x;
				funct5 = 'x;
				imm = imm_a_plus_b;
				csrimm = 'x;
			end

			// auipc, load
			27'b00101_???_???????_00000_???_1_1_?_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b00010;
				funct3 = b_funct3;
				funct7 = 7'b0000000;
				funct5 = 'x;
				imm = imm_a_plus_b;
				csrimm = 'x;
			end

			// lui, load
			27'b01101_???_???????_00000_???_1_1_?_?: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = b_opcode;
				funct3 = b_funct3;
				funct7 = 'x;
				funct5 = 'x;
				imm = imm_a_plus_b;
				csrimm = 'x;
			end

			// add, load
			27'b01100_000_0000000_00000_???_1_1_?_1: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b00010;
				funct3 = b_funct3;
				funct7 = 7'b0000001;
				funct5 = 'x;
				imm = 'x;
				csrimm = 'x;
			end

			// sh1add, load
			27'b01100_010_0010000_00000_???_1_1_?_1: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b00010;
				funct3 = b_funct3;
				funct7 = 7'b0000010;
				funct5 = 'x;
				imm = 'x;
				csrimm = 'x;
			end

			// sh2add, load
			27'b01100_100_0010000_00000_???_1_1_?_1: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b00010;
				funct3 = b_funct3;
				funct7 = 7'b0000011;
				funct5 = 'x;
				imm = 'x;
				csrimm = 'x;
			end

			// sh3add, load
			27'b01100_110_0010000_00000_???_1_1_?_1: begin
				performed_fusion = '1;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = 'x;
				opcode = 5'b00010;
				funct3 = b_funct3;
				funct7 = 7'b0000100;
				funct5 = 'x;
				imm = 'x;
				csrimm = 'x;
			end

			default: begin
				performed_fusion = '0;

				rd_decoded = a_rd_decoded;
				rs1_decoded = a_rs1_decoded;
				rs2_decoded = a_rs2_decoded;
				csr = a_csr;
				opcode = a_opcode;
				funct3 = a_funct3;
				funct7 = a_funct7;
				funct5 = a_funct5;
				imm = a_imm;
				csrimm = a_csrimm;
			end
		endcase

		if (performed_fusion) begin
			insts_num = 2'd2;
			case ({a_is_compressed, b_is_compressed})
				2'b00: insts_len = 4'd8;
				2'b01: insts_len = 4'd6;
				2'b10: insts_len = 4'd6;
				2'b11: insts_len = 4'd4;
			endcase
		end else begin
			insts_num = 2'd1;
			insts_len = a_is_compressed ? 4'd2 : 4'd4;
		end
	end
endmodule
