module rv_decompressing_decoder #(
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

		unique case (in[0+:2])
			2'b00: unique case (in[13+:3])
				3'b000: if (| in[2+:11]) begin
					// addi4spn
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd_({2'b01, in[2+:3]});
					rs1_(5'b00010);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(32'({in[7+:4], in[11+:2], in[5], in[6], 2'b0}));
				end else begin
					sigill = '1;
					is_compressed = 'x;
				end

				// fld
				3'b001: begin
					sigill = '1;
					is_compressed = 'x;
				end

				// lw
				3'b010: begin
					opcode = OpCode_Load;
					funct3 = 3'b010;

					rd_({2'b01, in[2+:3]});
					rs1_({2'b01, in[7+:3]});
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(32'({in[5], in[10+:3], in[6], 2'b0}));
				end

				3'b011: if (rv64) begin
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

				3'b100: unique case (in[11+:2])
					// lbu, lhu, lh
					2'b00: begin
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
					2'b01: begin
						opcode = OpCode_Store;
						funct3 = {2'b00, in[10]};

						rd_(5'b00000);
						rs1_({2'b01, in[7+:3]});
						rs2_({2'b01, in[2+:3]});
						csr_load = '0;
						csr_store = '0;

						imm_(32'({in[5], ~in[10] & in[6]}));
					end

					default: begin
						sigill = '1;
						is_compressed = 'x;
					end
				endcase

				// fsd
				3'b101: begin
					sigill = '1;
					is_compressed = 'x;
				end

				// sw
				3'b110: begin
					opcode = OpCode_Store;
					funct3 = 3'b010;

					rd_(5'b00000);
					rs1_({2'b01, in[7+:3]});
					rs2_({2'b01, in[2+:3]});
					csr_load = '0;
					csr_store = '0;

					imm_(32'({in[5], in[10+:3], in[6], 2'b0}));
				end

				3'b111: if (rv64) begin
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
			endcase

			2'b01: unique casez (in[13+:3])
				// addi, li
				3'b0?0: begin
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd_(in[7+:5]);
					rs1_({5{~in[14]}} & in[7+:5]);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(unsigned'(32'(signed'({in[12], in[2+:5]}))));
				end

				3'b001: if (rv64) begin
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

				3'b011: if (in[7+:5] == 5'b00010) begin
					// addi16sp
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd_(in[7+:5]);
					rs1_(in[7+:5]);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(unsigned'(32'(signed'({in[12], in[3+:2], in[5], in[2], in[6], 4'b0}))));
				end else begin
					// lui
					opcode = OpCode_Lui;

					rd_(in[7+:5]);
					rs1_(5'b00000);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(unsigned'(32'(signed'({in[12], in[2+:5], 12'b0}))));
				end

				3'b100: unique casez (in[10+:2])
					// srli, srai
					2'b0?: if (!rv64 && in[12]) begin
						sigill = '1;
						is_compressed = 'x;
					end else begin
						opcode = OpCode_OpImm;
						funct3 = 3'b101;
						funct7 = {1'b0, in[10], 4'b0000, in[12]};

						rd_({2'b01, in[7+:3]});
						rs1_({2'b01, in[7+:3]});
						rs2_(5'b00000);
						csr_load = '0;
						csr_store = '0;

						imm_(32'({in[10], 4'b0000, in[12], in[2+:5]}));
					end

					// andi
					2'b10: begin
						opcode = OpCode_OpImm;
						funct3 = 3'b111;

						rd_({2'b01, in[7+:3]});
						rs1_({2'b01, in[7+:3]});
						rs2_(5'b00000);
						csr_load = '0;
						csr_store = '0;

						imm_(unsigned'(32'(signed'({in[12], in[2+:5]}))));
					end

					2'b11: unique casez ({in[12], in[5+:2]})
						// sub, xor, or, and
						3'b0??: begin
							opcode = OpCode_Op;
							funct3 = {| in[5+:2], in[6], & in[5+:2]};
							funct7 = {1'b0, ~| in[5+:2], 5'b00000};

							rd_({2'b01, in[7+:3]});
							rs1_({2'b01, in[7+:3]});
							rs2_({2'b01, in[2+:3]});
							csr_load = '0;
							csr_store = '0;
						end

						3'b10?: if (rv64) begin
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

						// mul
						3'b110: begin
							opcode = OpCode_Op;
							funct3 = 3'b000;
							funct7 = 7'b0000001;

							rd_({2'b01, in[7+:3]});
							rs1_({2'b01, in[7+:3]});
							rs2_({2'b01, in[2+:3]});
							csr_load = '0;
							csr_store = '0;
						end

						3'b111: unique casez (in[2+:3])
							// zext.b
							3'b000: begin
								opcode = OpCode_OpImm;
								funct3 = 3'b111;

								rd_({2'b01, in[7+:3]});
								rs1_({2'b01, in[7+:3]});
								rs2_(5'b00000);
								csr_load = '0;
								csr_store = '0;

								imm_(32'(8'('1)));
							end

							// sext.b, sext.h
							3'b0?1: begin
								opcode = OpCode_OpImm;
								funct3 = 3'b001;
								funct7 = 7'b0110000;

								rd_({2'b01, in[7+:3]});
								rs1_({2'b01, in[7+:3]});
								rs2_(5'b00000);
								csr_load = '0;
								csr_store = '0;

								imm_(32'({11'b01100000010, in[3]}));
							end

							// zext.h
							3'b010: begin
								opcode = rv64 ? OpCode_Op32 : OpCode_Op;
								funct3 = 3'b100;
								funct7 = 7'b0000100;
								funct5 = 5'b00000;

								rd_({2'b01, in[7+:3]});
								rs1_({2'b01, in[7+:3]});
								rs2_(5'b00000);
								csr_load = '0;
								csr_store = '0;
							end

							3'b100: if (rv64) begin
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
							3'b101: begin
								opcode = OpCode_OpImm;
								funct3 = 3'b100;

								rd_({2'b01, in[7+:3]});
								rs1_({2'b01, in[7+:3]});
								rs2_(5'b00000);
								csr_load = '0;
								csr_store = '0;

								imm_(32'('1));
							end

							default: begin
								sigill = '1;
								is_compressed = 'x;
							end
						endcase
					endcase
				endcase

				// j
				3'b101: begin
					opcode = OpCode_Jal;

					rd_(5'b00000);
					rs1_(5'b00000);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(unsigned'(32'(signed'({in[12], in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0}))));
				end

				// beqz, bnez
				3'b11?: begin
					opcode = OpCode_Branch;
					funct3 = {2'b00, in[13]};

					rd_(5'b00000);
					rs1_({2'b01, in[7+:3]});
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(unsigned'(32'(signed'({in[12], in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0}))));
				end
			endcase

			2'b10: unique case (in[13+:3])
				// slli
				3'b000: if (!rv64 && in[12]) begin
					sigill = '1;
					is_compressed = 'x;
				end else begin
					opcode = OpCode_OpImm;
					funct3 = 3'b001;

					rd_(in[7+:5]);
					rs1_(in[7+:5]);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(32'({in[12], in[2+:5]}));
				end

				// fldsp
				3'b001: begin
					sigill = '1;
					is_compressed = 'x;
				end

				// lwsp
				3'b010: begin
					opcode = OpCode_Load;
					funct3 = 3'b010;

					rd_(in[7+:5]);
					rs1_(5'b00010);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(32'({in[2+:2], in[12], in[4+:3], 2'b0}));
				end

				3'b011: if (rv64) begin
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

				3'b100: unique case ({in[7] | in[8] | in[9] | in[10] | in[11], in[2] | in[3] | in[4] | in[5] | in[6]})
					2'b00: if (in[12]) begin
						// ebreak
						opcode = OpCode_System;
						funct3 = 3'b000;
						funct7 = 7'b0000000;
						funct5 = 5'b00001;

						rd_(5'b00000);
						rs1_(5'b00000);
						rs2_(5'b00000);
						csr_load = '0;
						csr_store = '0;
					end else begin
						sigill = '1;
						is_compressed = 'x;
					end

					// jr, jalr
					2'b10: begin
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
					2'b11: begin
						opcode = OpCode_Op;
						funct3 = 3'b000;
						funct7 = 7'b0000000;

						rd_(in[7+:5]);
						rs1_({5{in[12]}} & in[15+:5]);
						rs2_(in[2+:5]);
						csr_load = '0;
						csr_store = '0;
					end

					default: begin
						sigill = '1;
						is_compressed = 'x;
					end
				endcase

				// fsdsp
				3'b101: begin
					sigill = '1;
					is_compressed = 'x;
				end

				// swsp
				3'b110: begin
					opcode = OpCode_Store;
					funct3 = 3'b010;

					rd_(5'b00000);
					rs1_(5'b00010);
					rs2_(in[2+:5]);
					csr_load = '0;
					csr_store = '0;

					imm_(32'({in[7+:2], in[9+:4], 2'b0}));
				end

				3'b111: if (rv64) begin
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
			endcase

			2'b11: unique casez (in[2+:5])
				// op, op-32
				5'b011?0: begin
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
				5'b00000,
				// misc-mem
				5'b00011,
				// op-imm, op-imm-32
				5'b001?0,
				// jalr
				5'b11001: begin
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
				5'b01000: begin
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
				5'b11000: begin
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
				5'b0?101: begin
					opcode = in[2+:5];

					rd_(in[7+:5]);
					rs1_(5'b00000);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_({in[12+:20], 12'b0});
				end

				// jal
				5'b11011: begin
					opcode = in[2+:5];

					rd_(in[7+:5]);
					rs1_(5'b00000);
					rs2_(5'b00000);
					csr_load = '0;
					csr_store = '0;

					imm_(unsigned'(32'(signed'({in[31], in[12+:8], in[20], in[21+:10], 1'b0}))));
				end

				// system
				5'b11100: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];

					unique case (funct3)
						// ebreak, ecall
						3'b000: begin
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd_(5'b00000);
							rs1_(5'b00000);
							rs2_(5'b00000);
							csr_load = '0;
							csr_store = '0;
						end

						// csrrw
						3'b001: begin
							rd_(in[7+:5]);
							rs1_(in[15+:5]);
							rs2_(5'b00000);
							csr = in[20+:12];
							csr_load = | in[7+:5];
							csr_store = '1;
						end

						// csrrs
						3'b010: begin
							rd_(in[7+:5]);
							rs1_(in[15+:5]);
							rs2_(5'b00000);
							csr = in[20+:12];
							csr_load = '1;
							csr_store = | in[15+:5];
						end

						// csrrc
						3'b011: begin
							rd_(in[7+:5]);
							rs1_(in[15+:5]);
							rs2_(5'b00000);
							csr = in[20+:12];
							csr_load = '1;
							csr_store = | in[15+:5];
						end

						// csrrwi
						3'b101: begin
							rd_(in[7+:5]);
							rs1_(5'b00000);
							rs2_(5'b00000);
							csr = in[20+:12];
							csrimm = in[15+:5];
							csr_load = | in[7+:5];
							csr_store = '1;
						end

						// csrrsi
						3'b110: begin
							rd_(in[7+:5]);
							rs1_(5'b00000);
							rs2_(5'b00000);
							csr = in[20+:12];
							csrimm = in[15+:5];
							csr_load = '1;
							csr_store = | in[15+:5];
						end

						// csrrci
						3'b111: begin
							rd_(in[7+:5]);
							rs1_(5'b00000);
							rs2_(5'b00000);
							csr = in[20+:12];
							csrimm = in[15+:5];
							csr_load = '1;
							csr_store = | in[15+:5];
						end

						default: begin
							sigill = '1;
							is_compressed = 'x;

							opcode = 'x;
							funct3 = 'x;
						end
					endcase
				end

				default: begin
					sigill = '1;
					is_compressed = 'x;
				end
			endcase
		endcase
	end
endmodule
