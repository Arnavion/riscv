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
		csr = 'x;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		imm = 'x;
		csrimm = 'x;

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
					imm = rv64 ?
						{54'b0, in[7+:4], in[11+:2], in[5], in[6], 2'b00} :
						{22'b0, in[7+:4], in[11+:2], in[5], in[6], 2'b00};
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
					imm = rv64 ?
						{56'b0, in[5+:2], in[10+:3], 3'b000} :
						{24'b0, in[5+:2], in[10+:3], 3'b000};
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
					imm = rv64 ?
						{57'b0, in[5], in[10+:3], in[6], 2'b00} :
						{25'b0, in[5], in[10+:3], in[6], 2'b00};
				end

				// flw / ld
				5'b00011:
					if (rv64) begin
						// ld
						opcode = 5'b00000;
						funct3 = 3'b011;
						rd = {2'b01, in[2+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {56'b0, in[5+:2], in[10+:3], 3'b000};
					end else begin
						// flw
						opcode = 5'b00001;
						funct3 = 3'b010;
						rd = {2'b01, in[2+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {25'b0, in[5], in[10+:3], in[6], 2'b00};
					end

				// Zcb
				5'b00100: unique case ({in[10+:3]})
					// lbu
					3'b000: begin
						opcode = 5'b00000;
						funct3 = 3'b100;
						rd = {2'b01, in[2+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = rv64 ?
							{62'b0, in[5], in[6]} :
							{30'b0, in[5], in[6]};
					end

					// lhu / lh
					3'b001: begin
						opcode = 5'b00000;
						funct3 = {!in[6], 2'b01};
						rd = {2'b01, in[2+:3]};
						rd_decoded = rd_decoded_raw;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = rv64 ?
							{62'b0, in[5], 1'b0} :
							{30'b0, in[5], 1'b0};
					end

					// sb
					3'b010: begin
						opcode = 5'b01000;
						funct3 = 3'b000;
						rd_decoded = '0;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2 = {2'b01, in[2+:3]};
						rs2_decoded = rs2_decoded_raw;
						imm = rv64 ?
							{62'b0, in[5], in[6]} :
							{30'b0, in[5], in[6]};
					end

					// sh
					3'b011: begin
						opcode = 5'b01000;
						funct3 = 3'b001;
						rd_decoded = '0;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2 = {2'b01, in[2+:3]};
						rs2_decoded = rs2_decoded_raw;
						imm = rv64 ?
							{62'b0, in[5], 1'b0} :
							{30'b0, in[5], 1'b0};
					end

					default: begin
						sigill = '1;
						is_compressed = 'x;
					end
				endcase

				// fsd
				5'b00101: begin
					opcode = 5'b01001;
					funct3 = 3'b011;
					rd_decoded = '0;
					rs1 = {2'b01, in[7+:3]};
					rs1_decoded = rs1_decoded_raw;
					rs2 = {2'b01, in[2+:3]};
					rs2_decoded = rs2_decoded_raw;
					imm = rv64 ?
						{56'b0, in[5+:2], in[12], in[10+:2], 3'b000} :
						{24'b0, in[5+:2], in[12], in[10+:2], 3'b000};
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
					imm = rv64 ?
						{57'b0, in[5], in[12], in[10+:2], in[6], 2'b00} :
						{25'b0, in[5], in[12], in[10+:2], in[6], 2'b00};
				end

				// fsw / sd
				5'b00111:
					if (rv64) begin
						// sd
						opcode = 5'b01000;
						funct3 = 3'b011;
						rd_decoded = '0;
						rs1 = {2'b01, in[7+:3]};
						rs1_decoded = rs1_decoded_raw;
						rs2 = {2'b01, in[2+:3]};
						rs2_decoded = rs2_decoded_raw;
						imm = {56'b0, in[5+:2], in[12], in[10+:2], 3'b000};
					end else begin
						// fsw
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
					imm = rv64 ?
						{{59{in[12]}}, in[2+:5]} :
						{{27{in[12]}}, in[2+:5]};
				end

				// jal / addiw
				5'b01001:
					if (rv64) begin
						// addiw
						opcode = 5'b00110;
						funct3 = 3'b000;
						rd = in[7+:5];
						rd_decoded = rd_decoded_raw;
						rs1 = in[7+:5];
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {{59{in[12]}}, in[2+:5]};
					end else begin
						// jal
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
					imm = rv64 ?
						{{59{in[12]}}, in[2+:5]} :
						{{27{in[12]}}, in[2+:5]};
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
						imm = rv64 ?
							{{55{in[12]}}, in[3+:2], in[5], in[2], in[6], 4'b0000} :
							{{23{in[12]}}, in[3+:2], in[5], in[2], in[6], 4'b0000};
					end else begin
						// lui
						opcode = 5'b01101;
						rd = in[7+:5];
						rd_decoded = rd_decoded_raw;
						rs1_decoded = '0;
						rs2_decoded = '0;
						imm = rv64 ?
							{{47{in[12]}}, in[2+:5], 12'b0} :
							{{15{in[12]}}, in[2+:5], 12'b0};
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
						imm = rv64 ?
							{58'b0, in[12], in[2+:5]} :
							{26'b0, in[12], in[2+:5]};
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
						imm = rv64 ?
							{52'b0, 6'b010000, in[12], in[2+:5]} :
							{20'b0, 6'b010000, in[12], in[2+:5]};
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
						imm = rv64 ?
							{{59{in[12]}}, in[2+:5]} :
							{{27{in[12]}}, in[2+:5]};
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

						// subw
						3'b100: begin
							opcode = 5'b01110;
							funct3 = 3'b000;
							funct7 = 7'b0100000;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

						// addw
						3'b101: begin
							opcode = 5'b01110;
							funct3 = 3'b000;
							funct7 = 7'b000000;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

						// mul
						3'b110: begin
							opcode = 5'b01100;
							funct3 = 3'b000;
							funct7 = 7'b0000001;
							rd = {2'b01, in[7+:3]};
							rd_decoded = rd_decoded_raw;
							rs1 = {2'b01, in[7+:3]};
							rs1_decoded = rs1_decoded_raw;
							rs2 = {2'b01, in[2+:3]};
							rs2_decoded = rs2_decoded_raw;
						end

						3'b111: unique case (in[2+:3])
							// zext.b
							3'b000: begin
								opcode = 5'b00100;
								funct3 = 3'b111;
								rd = {2'b01, in[7+:3]};
								rd_decoded = rd_decoded_raw;
								rs1 = {2'b01, in[7+:3]};
								rs1_decoded = rs1_decoded_raw;
								rs2_decoded = '0;
								imm = rv64 ? 64'b000011111111 : 32'b000011111111;
							end

							// sext.b
							3'b001: begin
								opcode = 5'b00100;
								funct3 = 3'b001;
								funct7 = 7'b0110000;
								funct5 = 5'b00100;
								rd = {2'b01, in[7+:3]};
								rd_decoded = rd_decoded_raw;
								rs1 = {2'b01, in[7+:3]};
								rs1_decoded = rs1_decoded_raw;
								rs2_decoded = '0;
							end

							// zext.h
							3'b010: begin
								opcode = rv64 ? 5'b01110 : 5'b01100;
								funct3 = 3'b100;
								funct7 = 7'b0000100;
								funct5 = 5'b00000;
								rd = {2'b01, in[7+:3]};
								rd_decoded = rd_decoded_raw;
								rs1 = {2'b01, in[7+:3]};
								rs1_decoded = rs1_decoded_raw;
								rs2_decoded = '0;
							end

							// sext.h
							3'b011: begin
								opcode = 5'b00100;
								funct3 = 3'b001;
								funct7 = 7'b0110000;
								funct5 = 5'b00101;
								rd = {2'b01, in[7+:3]};
								rd_decoded = rd_decoded_raw;
								rs1 = {2'b01, in[7+:3]};
								rs1_decoded = rs1_decoded_raw;
								rs2_decoded = '0;
							end

							// zext.w
							3'b100: begin
								opcode = 5'b01110;
								funct3 = 3'b000;
								funct7 = 7'b0000100;
								rd = {2'b01, in[7+:3]};
								rd_decoded = rd_decoded_raw;
								rs1 = {2'b01, in[7+:3]};
								rs1_decoded = rs1_decoded_raw;
								rs2 = 5'b00000;
								rs2_decoded = rs2_decoded_raw;
							end

							// not
							3'b101: begin
								opcode = 5'b00100;
								funct3 = 3'b100;
								rd = {2'b01, in[7+:3]};
								rd_decoded = rd_decoded_raw;
								rs1 = {2'b01, in[7+:3]};
								rs1_decoded = rs1_decoded_raw;
								rs2_decoded = '0;
								imm = -1;
							end

							default: begin
								sigill = '1;
								is_compressed = 'x;
							end
						endcase
					endcase
				endcase

				// j
				5'b01101: begin
					opcode = 5'b11011;
					rd = 5'b00000;
					rd_decoded = rd_decoded_raw;
					rs1_decoded = '0;
					rs2_decoded = '0;
					imm = rv64 ?
						{{53{in[12]}}, in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0} :
						{{21{in[12]}}, in[8], in[9+:2], in[6], in[7], in[2], in[11], in[3+:3], 1'b0};
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
					imm = rv64 ?
						{{56{in[12]}}, in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0} :
						{{24{in[12]}}, in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0};
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
					imm = rv64 ?
						{{56{in[12]}}, in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0} :
						{{24{in[12]}}, in[5+:2], in[2], in[10+:2], in[3+:2], 1'b0};
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
					imm = rv64 ?
						{58'b0, in[12], in[2+:5]} :
						{26'b0, in[12], in[2+:5]};
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
					imm = rv64 ?
						{55'b0, in[4], in[2+:2], in[12], in[5+:2], 3'b000} :
						{23'b0, in[4], in[2+:2], in[12], in[5+:2], 3'b000};
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
					imm = rv64 ?
						{56'b0, in[2+:2], in[12], in[4+:3], 2'b00} :
						{24'b0, in[2+:2], in[12], in[4+:3], 2'b00};
				end

				// flwsp / ldsp
				5'b10011:
					if (rv64) begin
						// ldsp
						opcode = 5'b00000;
						funct3 = 3'b011;
						rd = in[7+:5];
						rd_decoded = rd_decoded_raw;
						rs1 = 5'b00010;
						rs1_decoded = rs1_decoded_raw;
						rs2_decoded = '0;
						imm = {55'b0, in[4], in[2+:2], in[12], in[5+:2], 3'b000};
					end else begin
						// flwsp
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
					imm = rv64 ?
						{55'b0, in[9], in[7+:2], in[12], in[10+:2], 3'b000} :
						{23'b0, in[9], in[7+:2], in[12], in[10+:2], 3'b000};
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
					imm = rv64 ?
						{56'b0, in[7+:2], in[12], in[9+:3], 2'b00} :
						{24'b0, in[7+:2], in[12], in[9+:3], 2'b00};
				end

				// fswsp / sdsp
				5'b10111:
					if (rv64) begin
						// sdsp
						opcode = 5'b01000;
						funct3 = 3'b011;
						rd_decoded = '0;
						rs1 = 5'b00010;
						rs1_decoded = rs1_decoded_raw;
						rs2 = in[2+:5];
						rs2_decoded = rs2_decoded_raw;
						imm = {55'b0, in[9], in[7+:2], in[12], in[10+:2], 3'b000};
					end else begin
						// fswsp
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
						5'b01100, // op
						5'b01110: // op-32
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
						5'b00110, // op-imm-32
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
							imm = rv64 ?
								{{52{in[31]}}, in[20+:12]} :
								{{20{in[31]}}, in[20+:12]};
							csr = in[20+:12];
							csrimm = in[15+:5];
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
							imm = rv64 ?
								{{52{in[31]}}, in[25+:7], in[7+:5]} :
								{{20{in[31]}}, in[25+:7], in[7+:5]};
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
							imm = rv64 ?
								{{51{in[31]}}, in[31], in[7], in[25+:6], in[8+:4], 1'b0} :
								{{19{in[31]}}, in[31], in[7], in[25+:6], in[8+:4], 1'b0};
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
							imm = rv64 ?
								{{32{in[31]}}, in[12+:20], 12'b0} :
								{in[12+:20], 12'b0};
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
							imm = rv64 ?
								{{43{in[31]}}, in[31], in[12+:8], in[20], in[21+:10], 1'b0} :
								{{11{in[31]}}, in[31], in[12+:8], in[20], in[21+:10], 1'b0};
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
