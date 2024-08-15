module rv_decompressing_decoder (
	input bit[31:0] in,

	output bit sigill,
	output logic is_compressed,
	output logic[31:0] rd_decoded,
	output logic[31:0] rs1_decoded,
	output logic[31:0] rs2_decoded,
	output bit[4:0] opcode,
	output bit[2:0] funct3,
	output bit[6:0] funct7,
	output bit[4:0] funct5,
	output logic[31:0] imm
);
	logic[4:0] rd;
	wire[31:0] rd_decoded_raw;
	reg_decoder rd_decoder (rd, rd_decoded_raw);

	logic[4:0] rs1;
	wire[31:0] rs1_decoded_raw;
	reg_decoder rs1_decoder (rs1, rs1_decoded_raw);

	logic[4:0] rs2;
	wire[31:0] rs2_decoded_raw;
	reg_decoder rs2_decoder (rs2, rs2_decoded_raw);

	always_comb begin
		rd = 'x;
		rd_decoded = 'x;
		rs1 = 'x;
		rs1_decoded = 'x;
		rs2 = 'x;
		rs2_decoded = 'x;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		imm = 'x;

		if (in[0+:16] == '0) begin
			sigill = '1;
			is_compressed = 'x;

		end else begin
			sigill = '0;
			is_compressed = '1;

			unique casez ({in[0+:2], in[13+:3]})
				// addi4spn
				5'b00000: begin
					opcode = 5'b00100;
					funct3 = 3'b000;
					rd = {2'b01, in[2+:3]};
					rd_decoded = rd_decoded_raw;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {22'b0, in[7+:4], in[11+:2], in[5], in[6], 2'b00};
				end

				// fld
				5'b00001: begin
					opcode = 5'b00001;
					funct3 = 3'b011;
					rd = {2'b01, in[2+:3]};
					rd_decoded = rd_decoded_raw;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {24'b0, in[5+:2], in[10+:3], 3'b000};
				end

				// lw
				5'b00010: begin
					opcode = 5'b00000;
					funct3 = 3'b010;
					rd = {2'b01, in[2+:3]};
					rd_decoded = rd_decoded_raw;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {25'b0, in[5], in[10+:3], in[6], 2'b00};
				end

				// flw
				5'b00011: begin
					opcode = 5'b00001;
					funct3 = 3'b010;
					rd = {2'b01, in[2+:3]};
					rd_decoded = rd_decoded_raw;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {25'b0, in[5], in[10+:3], in[6], 2'b00};
				end

				5'b00100: begin
					sigill = '1;
					is_compressed = 'x;
				end

				// fsd
				5'b00101: begin
					opcode = 5'b01001;
					funct3 = 3'b011;
					rd_decoded = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2 = {2'b01, in[2+:3]};
					rs2_decoded = rs2_decoded_raw;
					imm = {24'b0, in[5+:2], in[12], in[10+:2], 3'b000};
				end

				// sw
				5'b00110: begin
					opcode = 5'b01000;
					funct3 = 3'b010;
					rd_decoded = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2 = {2'b01, in[2+:3]};
					rs2_decoded = rs2_decoded_raw;
					imm = {25'b0, in[5], in[12], in[10+:2], in[6], 2'b00};
				end

				// fsw
				5'b00111: begin
					opcode = 5'b01001;
					funct3 = 3'b010;
					rd_decoded = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2 = {2'b01, in[2+:3]};
					rs2_decoded = rs2_decoded_raw;
					imm = {25'b0, in[5], in[12], in[10+:2], in[6], 2'b00};
				end

				// addi
				5'b01000: begin
					opcode = 5'b00100;
					funct3 = 3'b000;
					rd = in[7+:5];
					rd_decoded = rd_decoded_raw;
					rs1 = in[7+:5];
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {{27{in[12]}}, in[2+:5]};
				end

				// jal
				5'b01001: begin
					opcode = 5'b11011;
					rd = 5'b00001;
					rd_decoded = rd_decoded_raw;
					rs1_decoded = '0;
					rs2_decoded = '0;
					imm = {{21{in[12]}}, in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0};
				end

				// li
				5'b01010: begin
					opcode = 5'b00100;
					funct3 = 3'b000;
					rd = in[7+:5];
					rd_decoded = rd_decoded_raw;
					rs1 = 5'b00000;
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {{27{in[12]}}, in[2+:5]};
				end

				// lui / addi16sp
				5'b01011:
					if (in[7+:5] == 5'b00010) begin
						// addi16sp
						opcode = 5'b00100;
						funct3 = 3'b000;
						rd = 5'b00010;
						rd_decoded = rd_decoded_raw;
						rs1 = 5'b00010;
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {{23{in[12]}}, in[3+:2], in[5], in[2], in[6], 4'b0000};
					end else begin
						// lui
						opcode = 5'b01101;
						rd = in[7+:5];
						rd_decoded = rd_decoded_raw;
						rs1_decoded = '0;
						rs2_decoded = '0;
						imm = {{15{in[12]}}, in[2+:5], 12'b0};
					end

				// misc-alu
				5'b01100: unique case (in[10+:2])
					// srli
					2'b00: begin
						opcode = 5'b00100;
						funct3 = 3'b101;
						funct7 = {6'b000000, in[12]};
						rd = {2'b01, in[7+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {26'b0, in[12], in[2+:5]};
					end

					// srai
					2'b01: begin
						opcode = 5'b00100;
						funct3 = 3'b101;
						funct7 = {6'b010000, in[12]};
						rd = {2'b01, in[7+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {20'b0, 6'b010000, in[12], in[2+:5]};
					end

					// andi
					2'b10: begin
						opcode = 5'b00100;
						funct3 = 3'b111;
						rd = {2'b01, in[7+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {{27{in[12]}}, in[2+:5]};
					end

					2'b11: unique case ({in[12], in[5+:2]})
						// sub
						3'b000: begin
							opcode = 5'b01100;
							funct3 = 3'b000;
							funct7 = 7'b0100000;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

						// xor
						3'b001: begin
							opcode = 5'b01100;
							funct3 = 3'b100;
							funct7 = 7'b0000000;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

						// or
						3'b010: begin
							opcode = 5'b01100;
							funct3 = 3'b110;
							funct7 = 7'b0000000;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

						// and
						3'b011: begin
							opcode = 5'b01100;
							funct3 = 3'b111;
							funct7 = 7'b0000000;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

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
					rd_decoded = rd_decoded_raw;
					rs1_decoded = '0;
					rs2_decoded = '0;
					imm = {{21{in[12]}}, in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0};
				end

				// beqz
				5'b01110: begin
					opcode = 5'b11000;
					funct3 = 3'b000;
					rd_decoded = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2 = 5'b00000;
					rs2_decoded = rs2_decoded_raw;
					imm = {{24{in[12]}}, in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0};
				end

				// bnez
				5'b01111: begin
					opcode = 5'b11000;
					funct3 = 3'b001;
					rd_decoded = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2 = 5'b00000;
					rs2_decoded = rs2_decoded_raw;
					imm = {{24{in[12]}}, in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0};
				end

				// slli
				5'b10000: begin
					opcode = 5'b00100;
					funct3 = 3'b001;
					rd = in[7+:5];
					rd_decoded = rd_decoded_raw;
					rs1 = in[7+:5];
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {26'b0, in[12], in[2+:5]};
				end

				// fldsp
				5'b10001: begin
					opcode = 5'b00001;
					funct3 = 3'b011;
					rd = in[7+:5];
					rd_decoded = rd_decoded_raw;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {23'b0, in[4], in[2+:2], in[12], in[5+:2], 3'b000};
				end

				// lwsp
				5'b10010: begin
					opcode = 5'b00000;
					funct3 = 3'b010;
					rd = in[7+:5];
					rd_decoded = rd_decoded_raw;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {24'b0, in[2+:2], in[12], in[4+:3], 2'b00};
				end

				// flwsp
				5'b10011: begin
					opcode = 5'b00001;
					funct3 = 3'b010;
					rd = in[7+:5];
					rd_decoded = rd_decoded_raw;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2_decoded = '0;
					imm = {24'b0, in[2+:2], in[12], in[4+:3], 2'b00};
				end

				// jr / jalr / mv / add / ebreak
				5'b10100: unique case ({in[12], (in[7] | in[8] | in[9] | in[10] | in[11]), (in[2] | in[3] | in[4] | in[5] | in[6])})
					// jr
					3'b010: begin
						opcode = 5'b11001;
						funct3 = 3'b000;
						rd = 5'b00000;
						rd_decoded = rd_decoded_raw;
						rs1 = in[15+:5];
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = '0;
					end

					// mv
					3'b011: begin
						opcode = 5'b01100;
						funct3 = 3'b000;
						funct7 = 7'b0000000;
						rd = in[7+:5];
						rd_decoded = rd_decoded_raw;
						rs1 = 5'b00000;
						rs1_decoded = rs1_decoded_raw;
						rs2 = in[2+:5];
						rs2_decoded = rs2_decoded_raw;
					end

					// ebreak
					3'b100: begin
						opcode = 5'b11100;
						funct3 = 3'b000;
						funct7 = 7'b0000000;
						funct5 = 5'b00001;
						rd_decoded = '0;
						rs1_decoded = '0;
						rs2_decoded = '0;
					end

					// jalr
					3'b110: begin
						opcode = 5'b11001;
						funct3 = 3'b000;
						rd = 5'b00001;
						rd_decoded = rd_decoded_raw;
						rs1 = in[15+:5];
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = '0;
					end

					// add
					3'b111: begin
						opcode = 5'b01100;
						funct3 = 3'b000;
						funct7 = 7'b0000000;
						rd = in[7+:5];
						rd_decoded = rd_decoded_raw;
						rs1 = in[15+:5];
						rs1_decoded = rs1_decoded_raw;
						rs2 = in[2+:5];
						rs2_decoded = rs2_decoded_raw;
					end

					default: begin
						sigill = '1;
						is_compressed = 'x;
					end
				endcase

				// fsdsp
				5'b10101: begin
					opcode = 5'b01001;
					funct3 = 3'b011;
					rd_decoded = '0;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2 = in[2+:5];
					rs2_decoded = rs2_decoded_raw;
					imm = {23'b0, in[9], in[7+:2], in[12], in[10+:2], 3'b000};
				end

				// swsp
				5'b10110: begin
					opcode = 5'b01000;
					funct3 = 3'b010;
					rd_decoded = '0;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2 = in[2+:5];
					rs2_decoded = rs2_decoded_raw;
					imm = {24'b0, in[7+:2], in[12], in[9+:3], 2'b00};
				end

				// fswsp
				5'b10111: begin
					opcode = 5'b01000;
					funct3 = 3'b010;
					rd_decoded = '0;
					rs1 = 5'b00010;
					rs1_decoded = rs1_decoded_raw;
					rs2 = in[2+:5];
					rs2_decoded = rs2_decoded_raw;
					imm = {24'b0, in[7+:2], in[12], in[9+:3], 2'b00};
				end

				5'b11???: begin
					is_compressed = '0;

					unique case (in[2+:5])
						5'b01100: // op
						begin
							opcode = in[2+:5];
							funct3 = in[12+:3];
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd = in[7+:5];
							rd_decoded = rd_decoded_raw;
							rs1 = in[15+:5];
							rs1_decoded = rs1_decoded_raw;
							rs2 = in[20+:5];
							rs2_decoded = rs2_decoded_raw;
						end

						5'b00000, // load
						5'b00100, // op-imm
						5'b00111, // misc-mem
						5'b11001, // jalr
						5'b11100: // system
						begin
							opcode = in[2+:5];
							funct3 = in[12+:3];
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd = in[7+:5];
							rd_decoded = rd_decoded_raw;
							rs1 = in[15+:5];
							rs1_decoded = rs1_decoded_raw;
							rs2_decoded = '0;
							imm = {{20{in[31]}}, in[20+:12]};
						end

						5'b01000: // store
						begin
							opcode = in[2+:5];
							funct3 = in[12+:3];
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd_decoded = '0;
							rs1 = in[15+:5];
							rs1_decoded = rs1_decoded_raw;
							rs2 = in[20+:5];
							rs2_decoded = rs2_decoded_raw;
							imm = {{20{in[31]}}, in[25+:7], in[7+:5]};
						end

						5'b11000: // branch
						begin
							opcode = in[2+:5];
							funct3 = in[12+:3];
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd_decoded = '0;
							rs1 = in[15+:5];
							rs1_decoded = rs1_decoded_raw;
							rs2 = in[20+:5];
							rs2_decoded = rs2_decoded_raw;
							imm = {{19{in[31]}}, in[31], in[7], in[25+:6], in[8+:4], 1'b0};
						end

						5'b00101, // auipc
						5'b01101: // lui
						begin
							opcode = in[2+:5];
							funct3 = in[12+:3];
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd = in[7+:5];
							rd_decoded = rd_decoded_raw;
							rs1_decoded = '0;
							rs2_decoded = '0;
							imm = {in[12+:20], 12'b0};
						end

						5'b11011: // jal
						begin
							opcode = in[2+:5];
							funct3 = in[12+:3];
							funct7 = in[25+:7];
							funct5 = in[20+:5];

							rd = in[7+:5];
							rd_decoded = rd_decoded_raw;
							rs1_decoded = '0;
							rs2_decoded = '0;
							imm = {{11{in[31]}}, in[31], in[12+:8], in[20], in[21+:10], 1'b0};
						end

						default: begin
							sigill = '1;
							is_compressed = 'x;
						end
					endcase
				end
			endcase
		end
	end
endmodule

module reg_decoder (
	input bit[4:0] in,
	output bit[31:0] out
);
	assign out = 32'b1 << in;
endmodule
