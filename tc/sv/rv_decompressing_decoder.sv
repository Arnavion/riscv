module rv_decompressing_decoder #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit[31:0] in,

	output bit sigill,
	output logic is_compressed,
	output logic[31:0] rd_decoded,
	output logic[31:0] rs1_decoded,
	output logic[31:0] rs2_decoded,
	output logic[11:0] csr,
	output bit[4:0] opcode,
	output bit[2:0] funct3,
	output bit[6:0] funct7,
	output bit[4:0] funct5,
	output logic[xlen - 1:0] imm,
	output logic[4:0] csrimm
);
	logic[4:0] rd;
	logic rd_enable;
	reg_decoder rd_decoder (rd, rd_enable, rd_decoded);

	logic[4:0] rs1;
	logic rs1_enable;
	reg_decoder rs1_decoder (rs1, rs1_enable, rs1_decoded);

	logic[4:0] rs2;
	logic rs2_enable;
	reg_decoder rs2_decoder (rs2, rs2_enable, rs2_decoded);

	always_comb begin
		sigill = '0;
		is_compressed = '1;

		rd = 'x;
		rd_enable = 'x;
		rs1 = 'x;
		rs1_enable = 'x;
		rs2 = 'x;
		rs2_enable = 'x;
		csr = 'x;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		imm = 'x;
		csrimm = 'x;

		unique casez ({in[0+:2], in[13+:3]})
			// addi4spn
			5'b00000: if (in[2+:11] == '0) begin
				sigill = '1;
				is_compressed = 'x;
			end else begin
				opcode = 5'b00100;
				funct3 = 3'b000;
				rd = {2'b01, in[2+:3]};
				rd_enable = '1;
				rs1 = 5'b00010;
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[11], in[5], in[6], 1'b0};
				imm[5+:6] = {1'b0, in[7+:4], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end

			// fld
			5'b00001: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// lw
			5'b00010: begin
				opcode = 5'b00000;
				funct3 = 3'b010;
				rd = {2'b01, in[2+:3]};
				rd_enable = '1;
				rs1 = {2'b01, in[7+:3]};
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], in[6], 1'b00};
				imm[5+:6] = {4'b0000, in[5], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end

			5'b00011: if (rv64) begin
				// ld
				opcode = 5'b00000;
				funct3 = 3'b011;
				rd = {2'b01, in[2+:3]};
				rd_enable = '1;
				rs1 = {2'b01, in[7+:3]};
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], 2'b00};
				imm[5+:6] = {3'b000, in[5+:2], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end else begin
				// flw
				sigill = '1;
				is_compressed = 'x;
			end

			5'b00100: unique case ({in[10+:3]})
				// lbu
				3'b000: begin
					opcode = 5'b00000;
					funct3 = 3'b100;
					rd = {2'b01, in[2+:3]};
					rd_enable = '1;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = in[6];
					imm[1+:4] = {3'b000, in[5]};
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// lhu / lh
				3'b001: begin
					opcode = 5'b00000;
					funct3 = {!in[6], 2'b01};
					rd = {2'b01, in[2+:3]};
					rd_enable = '1;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = 1'b0;
					imm[1+:4] = {3'b000, in[5]};
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// sb
				3'b010: begin
					opcode = 5'b01000;
					funct3 = 3'b000;
					rd_enable = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2 = {2'b01, in[2+:3]};
					rs2_enable = '1;

					imm[0] = in[6];
					imm[1+:4] = {3'b000, in[5]};
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// sh
				3'b011: begin
					opcode = 5'b01000;
					funct3 = 3'b001;
					rd_enable = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2 = {2'b01, in[2+:3]};
					rs2_enable = '1;

					imm[0] = 1'b0;
					imm[1+:4] = {3'b000, in[5]};
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				default: begin
					sigill = '1;
					is_compressed = 'x;
				end
			endcase

			// fsd
			5'b00101: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// sw
			5'b00110: begin
				opcode = 5'b01000;
				funct3 = 3'b010;
				rd_enable = '0;
				rs1 = {2'b01, in[7+:3]};
				rs1_enable = '1;
				rs2 = {2'b01, in[2+:3]};
				rs2_enable = '1;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], in[6], 1'b0};
				imm[5+:6] = {4'b00, in[5], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end

			5'b00111: if (rv64) begin
				// sd
				opcode = 5'b01000;
				funct3 = 3'b011;
				rd_enable = '0;
				rs1 = {2'b01, in[7+:3]};
				rs1_enable = '1;
				rs2 = {2'b01, in[2+:3]};
				rs2_enable = '1;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], 2'b00};
				imm[5+:6] = {3'b000, in[5+:2], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end else begin
				// fsw
				sigill = '1;
				is_compressed = 'x;
			end

			// addi
			5'b01000: begin
				opcode = 5'b00100;
				funct3 = 3'b000;
				rd = in[7+:5];
				rd_enable = '1;
				rs1 = in[7+:5];
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = in[2];
				imm[1+:4] = in[3+:4];
				imm[5+:6] = {6{in[12]}};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			5'b01001: if (rv64) begin
				// addiw
				opcode = 5'b00110;
				funct3 = 3'b000;
				rd = in[7+:5];
				rd_enable = '1;
				rs1 = in[7+:5];
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = in[2];
				imm[1+:4] = in[3+:4];
				imm[5+:6] = {6{in[12]}};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end else begin
				// jal
				opcode = 5'b11011;
				rd = 5'b00001;
				rd_enable = '1;
				rs1_enable = '0;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[11], in[3+:3]};
				imm[5+:6] = {in[8], in[9+:2], in[6], in[7], in[2]};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			// li
			5'b01010: begin
				opcode = 5'b00100;
				funct3 = 3'b000;
				rd = in[7+:5];
				rd_enable = '1;
				rs1 = 5'b00000;
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = in[2];
				imm[1+:4] = in[3+:4];
				imm[5+:6] = {6{in[12]}};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			5'b01011: if (in[7+:5] == 5'b00010) begin
				// addi16sp
				opcode = 5'b00100;
				funct3 = 3'b000;
				rd = 5'b00010;
				rd_enable = '1;
				rs1 = 5'b00010;
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[6], 3'b000};
				imm[5+:6] = {{2{in[12]}}, in[3+:2], in[5], in[2]};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end else begin
				// lui
				opcode = 5'b01101;
				rd = in[7+:5];
				rd_enable = '1;
				rs1_enable = '0;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = 4'b0000;
				imm[5+:6] = 6'b000000;
				imm[11] = 1'b0;
				imm[12+:8] = {{3{in[12]}}, in[2+:5]};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			// misc-alu
			5'b01100: unique case (in[10+:2])
				// srli
				2'b00: begin
					opcode = 5'b00100;
					funct3 = 3'b101;
					funct7 = {6'b000000, in[12]};
					rd = {2'b01, in[7+:3]};
					rd_enable = '1;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {5'b00000, in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// srai
				2'b01: begin
					opcode = 5'b00100;
					funct3 = 3'b101;
					funct7 = {6'b010000, in[12]};
					rd = {2'b01, in[7+:3]};
					rd_enable = '1;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {5'b10000, in[12]};
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// andi
				2'b10: begin
					opcode = 5'b00100;
					funct3 = 3'b111;
					rd = {2'b01, in[7+:3]};
					rd_enable = '1;
					rs1 = {2'b01, in[7+:3]};
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = in[2];
					imm[1+:4] = in[3+:4];
					imm[5+:6] = {6{in[12]}};
					imm[11] = in[12];
					imm[12+:8] = {8{in[12]}};
					imm[20+:11] = {11{in[12]}};
					imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
				end

				2'b11: unique case ({in[12], in[5+:2]})
					// sub
					3'b000: begin
						opcode = 5'b01100;
						funct3 = 3'b000;
						funct7 = 7'b0100000;
						rd = {2'b01, in[7+:3]};
						rd_enable = '1;
						rs1 = {2'b01, in[7+:3]};
						rs1_enable = '1;
						rs2 = {2'b01, in[2+:3]};
						rs2_enable = '1;
					end

					// xor
					3'b001: begin
						opcode = 5'b01100;
						funct3 = 3'b100;
						funct7 = 7'b0000000;
						rd = {2'b01, in[7+:3]};
						rd_enable = '1;
						rs1 = {2'b01, in[7+:3]};
						rs1_enable = '1;
						rs2 = {2'b01, in[2+:3]};
						rs2_enable = '1;
					end

					// or
					3'b010: begin
						opcode = 5'b01100;
						funct3 = 3'b110;
						funct7 = 7'b0000000;
						rd = {2'b01, in[7+:3]};
						rd_enable = '1;
						rs1 = {2'b01, in[7+:3]};
						rs1_enable = '1;
						rs2 = {2'b01, in[2+:3]};
						rs2_enable = '1;
					end

					// and
					3'b011: begin
						opcode = 5'b01100;
						funct3 = 3'b111;
						funct7 = 7'b0000000;
						rd = {2'b01, in[7+:3]};
						rd_enable = '1;
						rs1 = {2'b01, in[7+:3]};
						rs1_enable = '1;
						rs2 = {2'b01, in[2+:3]};
						rs2_enable = '1;
					end

					// subw
					3'b100: if (rv64) begin
						opcode = 5'b01110;
						funct3 = 3'b000;
						funct7 = 7'b0100000;
						rd = {2'b01, in[7+:3]};
						rd_enable = '1;
						rs1 = {2'b01, in[7+:3]};
						rs1_enable = '1;
						rs2 = {2'b01, in[2+:3]};
						rs2_enable = '1;
					end else begin
						sigill = '1;
						is_compressed = 'x;
					end

					// addw
					3'b101: if (rv64) begin
						opcode = 5'b01110;
						funct3 = 3'b000;
						funct7 = 7'b000000;
						rd = {2'b01, in[7+:3]};
						rd_enable = '1;
						rs1 = {2'b01, in[7+:3]};
						rs1_enable = '1;
						rs2 = {2'b01, in[2+:3]};
						rs2_enable = '1;
					end else begin
						sigill = '1;
						is_compressed = 'x;
					end

					3'b111: unique case (in[2+:3])
						// zext.b
						3'b000: begin
							opcode = 5'b00100;
							funct3 = 3'b111;
							rd = {2'b01, in[7+:3]};
							rd_enable = '1;
							rs1 = {2'b01, in[7+:3]};
							rs1_enable = '1;
							rs2_enable = '0;

							imm[0] = 1'b1;
							imm[1+:4] = 4'b1111;
							imm[5+:6] = 6'b000111;
							imm[11] = 1'b0;
							imm[12+:8] = 8'b00000000;
							imm[20+:11] = 11'b00000000000;
							imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
						end

						// zext.w
						3'b100: if (rv64) begin
							opcode = 5'b01110;
							funct3 = 3'b000;
							funct7 = 7'b0000100;
							rd = {2'b01, in[7+:3]};
							rd_enable = '1;
							rs1 = {2'b01, in[7+:3]};
							rs1_enable = '1;
							rs2 = 5'b00000;
							rs2_enable = '1;
						end else begin
							sigill = '1;
							is_compressed = 'x;
						end

						// not
						3'b101: begin
							opcode = 5'b00100;
							funct3 = 3'b100;
							rd = {2'b01, in[7+:3]};
							rd_enable = '1;
							rs1 = {2'b01, in[7+:3]};
							rs1_enable = '1;
							rs2_enable = '0;

							imm[0] = 1'b1;
							imm[1+:4] = 4'b1111;
							imm[5+:6] = 6'b111111;
							imm[11] = 1'b1;
							imm[12+:8] = 8'b11111111;
							imm[20+:11] = 11'b11111111111;
							imm[31+:xlen - 31] = {(xlen - 31){1'b1}};
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
			5'b01101: begin
				opcode = 5'b11011;
				rd = 5'b00000;
				rd_enable = '1;
				rs1_enable = '0;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[11], in[3+:3]};
				imm[5+:6] = {in[8], in[9+:2], in[6], in[7], in[2]};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			// beqz
			5'b01110: begin
				opcode = 5'b11000;
				funct3 = 3'b000;
				rd_enable = '0;
				rs1 = {2'b01, in[7+:3]};
				rs1_enable = '1;
				rs2 = 5'b00000;
				rs2_enable = '1;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], in[3+:2]};
				imm[5+:6] = {{3{in[12]}}, in[5+:2], in[2]};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			// bnez
			5'b01111: begin
				opcode = 5'b11000;
				funct3 = 3'b001;
				rd_enable = '0;
				rs1 = {2'b01, in[7+:3]};
				rs1_enable = '1;
				rs2 = 5'b00000;
				rs2_enable = '1;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], in[3+:2]};
				imm[5+:6] = {{3{in[12]}}, in[5+:2], in[2]};
				imm[11] = in[12];
				imm[12+:8] = {8{in[12]}};
				imm[20+:11] = {11{in[12]}};
				imm[31+:xlen - 31] = {(xlen - 31){in[12]}};
			end

			// slli
			5'b10000: begin
				opcode = 5'b00100;
				funct3 = 3'b001;
				rd = in[7+:5];
				rd_enable = '1;
				rs1 = in[7+:5];
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = in[2];
				imm[1+:4] = in[3+:4];
				imm[5+:6] = {5'b00000, in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end

			// fldsp
			5'b10001: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// lwsp
			5'b10010: begin
				opcode = 5'b00000;
				funct3 = 3'b010;
				rd = in[7+:5];
				rd_enable = '1;
				rs1 = 5'b00010;
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[4+:3], 1'b0};
				imm[5+:6] = {3'b000, in[2+:2], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end

			5'b10011: if (rv64) begin
				// ldsp
				opcode = 5'b00000;
				funct3 = 3'b011;
				rd = in[7+:5];
				rd_enable = '1;
				rs1 = 5'b00010;
				rs1_enable = '1;
				rs2_enable = '0;

				imm[0] = 1'b0;
				imm[1+:4] = {in[5+:2], 2'b00};
				imm[5+:6] = {2'b00, in[2+:3], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end else begin
				// flwsp
				sigill = '1;
				is_compressed = 'x;
			end

			5'b10100: unique case ({in[12], (in[7] | in[8] | in[9] | in[10] | in[11]), (in[2] | in[3] | in[4] | in[5] | in[6])})
				// jr
				3'b010: begin
					opcode = 5'b11001;
					funct3 = 3'b000;
					rd = 5'b00000;
					rd_enable = '1;
					rs1 = in[15+:5];
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = 1'b0;
					imm[1+:4] = 4'b0000;
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// mv
				3'b011: begin
					opcode = 5'b01100;
					funct3 = 3'b000;
					funct7 = 7'b0000000;
					rd = in[7+:5];
					rd_enable = '1;
					rs1 = 5'b00000;
					rs1_enable = '1;
					rs2 = in[2+:5];
					rs2_enable = '1;
				end

				// ebreak
				3'b100: begin
					opcode = 5'b11100;
					funct3 = 3'b000;
					funct7 = 7'b0000000;
					funct5 = 5'b00001;
					rd_enable = '0;
					rs1_enable = '0;
					rs2_enable = '0;
				end

				// jalr
				3'b110: begin
					opcode = 5'b11001;
					funct3 = 3'b000;
					rd = 5'b00001;
					rd_enable = '1;
					rs1 = in[15+:5];
					rs1_enable = '1;
					rs2_enable = '0;

					imm[0] = 1'b0;
					imm[1+:4] = 4'b0000;
					imm[5+:6] = 6'b000000;
					imm[11] = 1'b0;
					imm[12+:8] = 8'b00000000;
					imm[20+:11] = 11'b00000000000;
					imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
				end

				// add
				3'b111: begin
					opcode = 5'b01100;
					funct3 = 3'b000;
					funct7 = 7'b0000000;
					rd = in[7+:5];
					rd_enable = '1;
					rs1 = in[15+:5];
					rs1_enable = '1;
					rs2 = in[2+:5];
					rs2_enable = '1;
				end

				default: begin
					sigill = '1;
					is_compressed = 'x;
				end
			endcase

			// fsdsp
			5'b10101: begin
				sigill = '1;
				is_compressed = 'x;
			end

			// swsp
			5'b10110: begin
				opcode = 5'b01000;
				funct3 = 3'b010;
				rd_enable = '0;
				rs1 = 5'b00010;
				rs1_enable = '1;
				rs2 = in[2+:5];
				rs2_enable = '1;

				imm[0] = 1'b0;
				imm[1+:4] = {in[9+:3], 1'b0};
				imm[5+:6] = {3'b000, in[7+:2], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end

			5'b10111: if (rv64) begin
				// sdsp
				opcode = 5'b01000;
				funct3 = 3'b011;
				rd_enable = '0;
				rs1 = 5'b00010;
				rs1_enable = '1;
				rs2 = in[2+:5];
				rs2_enable = '1;

				imm[0] = 1'b0;
				imm[1+:4] = {in[10+:2], 2'b00};
				imm[5+:6] = {2'b00, in[7+:3], in[12]};
				imm[11] = 1'b0;
				imm[12+:8] = 8'b00000000;
				imm[20+:11] = 11'b00000000000;
				imm[31+:xlen - 31] = {(xlen - 31){1'b0}};
			end else begin
				// fswsp
				sigill = '1;
				is_compressed = 'x;
			end

			5'b11???: begin
				is_compressed = '0;

				unique casez (in[2+:5])
					5'b011?0: // op, op-32
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rd_enable = '1;
						rs1 = in[15+:5];
						rs1_enable = '1;
						rs2 = in[20+:5];
						rs2_enable = '1;
					end

					5'b00000, // load
					5'b001?0, // op-imm, op-imm-32
					5'b00111, // misc-mem
					5'b11001, // jalr
					5'b11100: // system
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rd_enable = '1;
						rs1 = in[15+:5];
						rs1_enable = '1;
						rs2_enable = '0;

						csr = in[20+:12];

						imm[0] = in[20];
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};

						csrimm = in[15+:5];
					end

					5'b01000: // store
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '0;
						rs1 = in[15+:5];
						rs1_enable = '1;
						rs2 = in[20+:5];
						rs2_enable = '1;

						imm[0] = in[7];
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

					5'b11000: // branch
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '0;
						rs1 = in[15+:5];
						rs1_enable = '1;
						rs2 = in[20+:5];
						rs2_enable = '1;

						imm[0] = 1'b0;
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[7];
						imm[12+:8] = {8{in[31]}};
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

					5'b0?101: // auipc, lui
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rd_enable = '1;
						rs1_enable = '0;
						rs2_enable = '0;

						imm[0] = 1'b0;
						imm[1+:4] = 4'b0000;
						imm[5+:6] = 6'b000000;
						imm[11] = 1'b0;
						imm[12+:8] = in[12+:8];
						imm[20+:11] = in[20+:11];
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

					5'b11011: // jal
					begin
						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rd_enable = '1;
						rs1_enable = '0;
						rs2_enable = '0;

						imm[0] = 1'b0;
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[20];
						imm[12+:8] = in[12+:8];
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
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

module reg_decoder (
	input bit[4:0] in,
	input bit enable,
	output bit[31:0] out
);
	assign out = enable ? 32'b1 << in : '0;
endmodule
