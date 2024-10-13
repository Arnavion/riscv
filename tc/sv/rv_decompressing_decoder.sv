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

	always_comb begin
		sigill = '0;
		is_compressed = '1;

		rd = 'x;
		rs1 = 'x;
		rs2 = 'x;
		csr = 'x;
		csr_load = 'x;
		csr_store = 'x;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		imm = 'x;
		csrimm = 'x;

		unique case (in[0+:2])
			2'b00: unique case (in[13+:3])
				3'b000: if (in[2+:11] == '0) begin
					sigill = '1;
					is_compressed = 'x;
				end else begin
					// addi4spn
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd = {2'b01, in[2+:3]};
					rs1 = 5'b00010;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[11], in[5], in[6], 1'b0};
					imm[5+:6] = {1'b0, in[7+:4], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
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

					rd = {2'b01, in[2+:3]};
					rs1 = {2'b01, in[7+:3]};
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], in[6], 1'b0};
					imm[5+:6] = {4'b0000, in[5], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end

				3'b011: if (rv64) begin
					// ld
					opcode = OpCode_Load;
					funct3 = 3'b011;

					rd = {2'b01, in[2+:3]};
					rs1 = {2'b01, in[7+:3]};
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], 2'b00};
					imm[5+:6] = {3'b000, in[5+:2], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end else begin
					// flw
					sigill = '1;
					is_compressed = 'x;
				end

				3'b100: unique case (in[10+:3])
					// lbu
					3'b000: begin
						opcode = OpCode_Load;
						funct3 = 3'b100;

						rd = {2'b01, in[2+:3]};
						rs1 = {2'b01, in[7+:3]};
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[6];
						imm[1+:4] = {3'b000, in[5]};
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
					end

					// lhu / lh
					3'b001: begin
						opcode = OpCode_Load;
						funct3 = {!in[6], 2'b01};

						rd = {2'b01, in[2+:3]};
						rs1 = {2'b01, in[7+:3]};
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = 1'b0;
						imm[1+:4] = {3'b000, in[5]};
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
					end

					// sb
					3'b010: begin
						opcode = OpCode_Store;
						funct3 = 3'b000;

						rd = 5'b00000;
						rs1 = {2'b01, in[7+:3]};
						rs2 = {2'b01, in[2+:3]};
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[6];
						imm[1+:4] = {3'b000, in[5]};
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
					end

					// sh
					3'b011: begin
						opcode = OpCode_Store;
						funct3 = 3'b001;

						rd = 5'b00000;
						rs1 = {2'b01, in[7+:3]};
						rs2 = {2'b01, in[2+:3]};
						csr_load = '0;
						csr_store = '0;

						imm[0] = 1'b0;
						imm[1+:4] = {3'b000, in[5]};
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
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

					rd = 5'b00000;
					rs1 = {2'b01, in[7+:3]};
					rs2 = {2'b01, in[2+:3]};
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], in[6], 1'b0};
					imm[5+:6] = {4'b00, in[5], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end

				3'b111: if (rv64) begin
					// sd
					opcode = OpCode_Store;
					funct3 = 3'b011;

					rd = 5'b00000;
					rs1 = {2'b01, in[7+:3]};
					rs2 = {2'b01, in[2+:3]};
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], 2'b00};
					imm[5+:6] = {3'b000, in[5+:2], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end else begin
					// fsw
					sigill = '1;
					is_compressed = 'x;
				end
			endcase

			2'b01: unique case (in[13+:3])
				// addi
				3'b000: begin
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd = in[7+:5];
					rs1 = in[7+:5];
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {6{in[12]}};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end

				3'b001: if (rv64) begin
					// addiw
					opcode = OpCode_OpImm32;
					funct3 = 3'b000;

					rd = in[7+:5];
					rs1 = in[7+:5];
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {6{in[12]}};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end else begin
					// jal
					opcode = OpCode_Jal;

					rd = 5'b00001;
					rs1 = 5'b00000;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[11], in[3+:3]};
					imm[5+:6] = {in[8], in[9+:2], in[6], in[7], in[2]};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end

				// li
				3'b010: begin
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd = in[7+:5];
					rs1 = 5'b00000;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {6{in[12]}};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end

				3'b011: if (in[7+:5] == 5'b00010) begin
					// addi16sp
					opcode = OpCode_OpImm;
					funct3 = 3'b000;

					rd = 5'b00010;
					rs1 = 5'b00010;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[6], 3'b000};
					imm[5+:6] = {{2{in[12]}}, in[3+:2], in[5], in[2]};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end else begin
					// lui
					opcode = OpCode_Lui;

					rd = in[7+:5];
					rs1 = 5'b00000;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = 4'b0000;
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = {{3{in[12]}}, in[2+:5]};
					imm[20+:12] = {12{in[12]}};
				end

				3'b100: unique case (in[10+:2])
					// srli
					2'b00: if (!rv64 && in[12]) begin
						sigill = '1;
						is_compressed = 'x;
					end else begin
						opcode = OpCode_OpImm;
						funct3 = 3'b101;
						funct7 = {6'b000000, in[12]};

						rd = {2'b01, in[7+:3]};
						rs1 = {2'b01, in[7+:3]};
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[2];
						imm[1+:4] = in[3+:4];
						imm[5+:6] = {5'b00000, in[12]};
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
					end

					// srai
					2'b01: if (!rv64 && in[12]) begin
						sigill = '1;
						is_compressed = 'x;
					end else begin
						opcode = OpCode_OpImm;
						funct3 = 3'b101;
						funct7 = {6'b010000, in[12]};

						rd = {2'b01, in[7+:3]};
						rs1 = {2'b01, in[7+:3]};
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[2];
						imm[1+:4] = in[3+:4];
						imm[5+:6] = {5'b10000, in[12]};
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
					end

					// andi
					2'b10: begin
						opcode = OpCode_OpImm;
						funct3 = 3'b111;

						rd = {2'b01, in[7+:3]};
						rs1 = {2'b01, in[7+:3]};
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[2];
						imm[1+:4] = in[3+:4];
						imm[5+:6] = {6{in[12]}};
						imm[11] = in[12];
						imm[12+:8] = {8{in[12]}};
						imm[20+:12] = {12{in[12]}};
					end

					2'b11: unique case ({in[12], in[5+:2]})
						// sub
						3'b000: begin
							opcode = OpCode_Op;
							funct3 = 3'b000;
							funct7 = 7'b0100000;

							rd = {2'b01, in[7+:3]};
							rs1 = {2'b01, in[7+:3]};
							rs2 = {2'b01, in[2+:3]};
							csr_load = '0;
							csr_store = '0;
						end

						// xor
						3'b001: begin
							opcode = OpCode_Op;
							funct3 = 3'b100;
							funct7 = 7'b0000000;

							rd = {2'b01, in[7+:3]};
							rs1 = {2'b01, in[7+:3]};
							rs2 = {2'b01, in[2+:3]};
							csr_load = '0;
							csr_store = '0;
						end

						// or
						3'b010: begin
							opcode = OpCode_Op;
							funct3 = 3'b110;
							funct7 = 7'b0000000;

							rd = {2'b01, in[7+:3]};
							rs1 = {2'b01, in[7+:3]};
							rs2 = {2'b01, in[2+:3]};
							csr_load = '0;
							csr_store = '0;
						end

						// and
						3'b011: begin
							opcode = OpCode_Op;
							funct3 = 3'b111;
							funct7 = 7'b0000000;

							rd = {2'b01, in[7+:3]};
							rs1 = {2'b01, in[7+:3]};
							rs2 = {2'b01, in[2+:3]};
							csr_load = '0;
							csr_store = '0;
						end

						3'b100: if (rv64) begin
							// subw
							opcode = OpCode_Op32;
							funct3 = 3'b000;
							funct7 = 7'b0100000;

							rd = {2'b01, in[7+:3]};
							rs1 = {2'b01, in[7+:3]};
							rs2 = {2'b01, in[2+:3]};
							csr_load = '0;
							csr_store = '0;
						end else begin
							sigill = '1;
							is_compressed = 'x;
						end

						3'b101: if (rv64) begin
							// addw
							opcode = OpCode_Op32;
							funct3 = 3'b000;
							funct7 = 7'b000000;

							rd = {2'b01, in[7+:3]};
							rs1 = {2'b01, in[7+:3]};
							rs2 = {2'b01, in[2+:3]};
							csr_load = '0;
							csr_store = '0;
						end else begin
							sigill = '1;
							is_compressed = 'x;
						end

						3'b111: unique case (in[2+:3])
							// zext.b
							3'b000: begin
								opcode = OpCode_OpImm;
								funct3 = 3'b111;

								rd = {2'b01, in[7+:3]};
								rs1 = {2'b01, in[7+:3]};
								rs2 = 5'b00000;
								csr_load = '0;
								csr_store = '0;

								imm[0] = 1'b1;
								imm[1+:4] = 4'b1111;
								imm[5+:6] = 6'b000111;
								imm[11] = 1'b0;
								imm[12+:8] = 8'b00000000;
								imm[20+:12] = 12'b000000000000;
							end

							3'b100: if (rv64) begin
								// zext.w
								opcode = OpCode_Op32;
								funct3 = 3'b000;
								funct7 = 7'b0000100;

								rd = {2'b01, in[7+:3]};
								rs1 = {2'b01, in[7+:3]};
								rs2 = 5'b00000;
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

								rd = {2'b01, in[7+:3]};
								rs1 = {2'b01, in[7+:3]};
								rs2 = 5'b00000;
								csr_load = '0;
								csr_store = '0;

								imm[0] = 1'b1;
								imm[1+:4] = 4'b1111;
								imm[5+:6] = 6'b111111;
								imm[11] = 1'b1;
								imm[12+:8] = 8'b11111111;
								imm[20+:12] = 12'b111111111111;
							end

							default: begin
								sigill = '1;
								is_compressed = 'x;
							end
						endcase

						default: begin
							sigill = '1;
							is_compressed = 'x;
						end
					endcase
				endcase

				// j
				3'b101: begin
					opcode = OpCode_Jal;

					rd = 5'b00000;
					rs1 = 5'b00000;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[11], in[3+:3]};
					imm[5+:6] = {in[8], in[9+:2], in[6], in[7], in[2]};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end

				// beqz
				3'b110: begin
					opcode = OpCode_Branch;
					funct3 = 3'b000;

					rd = 5'b00000;
					rs1 = {2'b01, in[7+:3]};
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], in[3+:2]};
					imm[5+:6] = {{3{in[12]}}, in[5+:2], in[2]};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
				end

				// bnez
				3'b111: begin
					opcode = OpCode_Branch;
					funct3 = 3'b001;

					rd = 5'b00000;
					rs1 = {2'b01, in[7+:3]};
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], in[3+:2]};
					imm[5+:6] = {{3{in[12]}}, in[5+:2], in[2]};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:12] = {12{in[12]}};
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

					rd = in[7+:5];
					rs1 = in[7+:5];
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {5'b00000, in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
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

					rd = in[7+:5];
					rs1 = 5'b00010;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[4+:3], 1'b0};
					imm[5+:6] = {3'b000, in[2+:2], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end

				3'b011: if (rv64) begin
					// ldsp
					opcode = OpCode_Load;
					funct3 = 3'b011;

					rd = in[7+:5];
					rs1 = 5'b00010;
					rs2 = 5'b00000;
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[5+:2], 2'b00};
					imm[5+:6] = {2'b00, in[2+:3], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
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

						rd = 5'b00000;
						rs1 = 5'b00000;
						rs2 = 5'b00000;
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

						rd = {4'b0000, in[12]};
						rs1 = in[15+:5];
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = 1'b0;
						imm[1+:4] = 4'b0000;
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = 8'b00000000;
						imm[20+:12] = 12'b000000000000;
					end

					// mv, add
					2'b11: begin
						opcode = OpCode_Op;
						funct3 = 3'b000;
						funct7 = 7'b0000000;

						rd = in[7+:5];
						rs1 = {5{in[12]}} & in[15+:5];
						rs2 = in[2+:5];
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

					rd = 5'b00000;
					rs1 = 5'b00010;
					rs2 = in[2+:5];
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[9+:3], 1'b0};
					imm[5+:6] = {3'b000, in[7+:2], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end

				3'b111: if (rv64) begin
					// sdsp
					opcode = OpCode_Store;
					funct3 = 3'b011;

					rd = 5'b00000;
					rs1 = 5'b00010;
					rs2 = in[2+:5];
					csr_load = '0;
					csr_store = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {in[10+:2], 2'b00};
					imm[5+:6] = {2'b00, in[7+:3], in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:12] = 12'b000000000000;
				end else begin
					// fswsp
					sigill = '1;
					is_compressed = 'x;
				end
			endcase

			2'b11: begin
				is_compressed = '0;

				unique casez (in[2+:5])
					5'b011?0: // op, op-32
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rs1 = in[15+:5];
						rs2 = in[20+:5];
						csr_load = '0;
						csr_store = '0;
					end

					5'b00000, // load
					5'b001?0, // op-imm, op-imm-32
					5'b00111, // misc-mem
					5'b11001: // jalr
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];

						rd = in[7+:5];
						rs1 = in[15+:5];
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[20];
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:12] = {12{in[31]}};
					end

					5'b11100: // system
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];

						rd = 5'b00000;
						rs1 = 5'b00000;
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						unique case (funct3)
							3'b000: // ebreak, ecall
							begin
								funct7 = in[25+:7];
								funct5 = in[20+:5];
							end

							3'b001: // csrrw
							begin
								rs1 = in[15+:5];
								csr = in[20+:12];
								csr_load = rd != '0;
								csr_store = '1;
							end

							3'b010: // csrrs
							begin
								rs1 = in[15+:5];
								csr = in[20+:12];
								csr_load = '1;
								csr_store = rs1 != '0;
							end

							3'b011: // csrrc
							begin
								rs1 = in[15+:5];
								csr = in[20+:12];
								csr_load = '1;
								csr_store = rs1 != '0;
							end

							3'b101: // csrrwi
							begin
								csr = in[20+:12];
								csrimm = in[15+:5];
								csr_load = rd != '0;
								csr_store = '1;
							end

							3'b110: // csrrsi
							begin
								csr = in[20+:12];
								csrimm = in[15+:5];
								csr_load = '1;
								csr_store = csrimm != '0;
							end

							3'b111: // csrrci
							begin
								csr = in[20+:12];
								csrimm = in[15+:5];
								csr_load = '1;
								csr_store = csrimm != '0;
							end

							default: begin
								sigill = '1;
								is_compressed = 'x;

								opcode = 'x;
								funct3 = 'x;

								rd = 'x;
								rs1 = 'x;
								rs2 = 'x;
								csr_load = 'x;
								csr_store = 'x;
							end
						endcase
					end

					5'b01000: // store
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];

						rd = 5'b00000;
						rs1 = in[15+:5];
						rs2 = in[20+:5];
						csr_load = '0;
						csr_store = '0;

						imm[0] = in[7];
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:12] = {12{in[31]}};
					end

					5'b11000: // branch
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];

						rd = 5'b00000;
						rs1 = in[15+:5];
						rs2 = in[20+:5];
						csr_load = '0;
						csr_store = '0;

						imm[0] = 1'b0;
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[7];
						imm[12+:8] = {8{in[31]}};
						imm[20+:12] = {12{in[31]}};
					end

					5'b0?101: // auipc, lui
					begin
						opcode = in[2+:5];

						rd = in[7+:5];
						rs1 = 5'b00000;
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = 1'b0;
						imm[1+:4] = 4'b0000;
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = in[12+:8];
						imm[20+:12] = in[20+:12];
					end

					5'b11011: // jal
					begin
						opcode = in[2+:5];

						rd = in[7+:5];
						rs1 = 5'b00000;
						rs2 = 5'b00000;
						csr_load = '0;
						csr_store = '0;

						imm[0] = 1'b0;
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[20];
						imm[12+:8] = in[12+:8];
						imm[20+:12] = {12{in[31]}};
					end

					default: begin
						sigill = '1;
						is_compressed = 'x;
					end
				endcase
			end
		endcase
	end
endmodule
