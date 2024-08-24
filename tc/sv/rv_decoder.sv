module rv_decoder (
	input bit[31:0] in,

	output bit sigill,
	output logic[4:0] rd,
	output logic[4:0] rs1,
	output logic[4:0] rs2,
	output logic[4:0] opcode,
	output logic[2:0] funct3,
	output logic[6:0] funct7,
	output logic[4:0] funct5,
	output logic[31:0] imm
);
	always_comb begin
		sigill = '1;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		rd = 'x;
		rs1 = 'x;
		rs2 = 'x;
		imm = 'x;

		if (in[0+:2] == 2'b11) begin
			unique casez (in[2+:5])
				5'b011?0: // op, op-32
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rs1 = in[15+:5];
						rs2 = in[20+:5];
					end

				5'b00000, // load
				5'b001?0, // op-imm, op-imm-32
				5'b00111, // misc-mem
				5'b11001: // jalr
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];

						rd = in[7+:5];
						rs1 = in[15+:5];
						rs2 = '0;

						imm[0] = in[20];
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:12] = {12{in[31]}};
					end

				5'b11100: // system
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];

						rd = '0;
						rs1 = '0;
						rs2 = '0;

						unique case (funct3)
							3'b000: // ebreak, ecall
							begin
								funct7 = in[25+:7];
								funct5 = in[20+:5];
							end

							default: begin
								sigill = '1;

								opcode = 'x;
								funct3 = 'x;

								rd = 'x;
								rs1 = 'x;
								rs2 = 'x;
							end
						endcase
					end

				5'b01000: // store
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = '0;
						rs1 = in[15+:5];
						rs2 = in[20+:5];

						imm[0] = in[7];
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:12] = {12{in[31]}};
					end

				5'b11000: // branch
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = '0;
						rs1 = in[15+:5];
						rs2 = in[20+:5];

						imm[0] = '0;
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[7];
						imm[12+:8] = {8{in[31]}};
						imm[20+:12] = {12{in[31]}};
					end

				5'b0?101: // auipc, lui
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rs1 = '0;
						rs2 = '0;

						imm[0] = '0;
						imm[1+:4] = '0;
						imm[5+:6] = '0;
						imm[11] = '0;
						imm[12+:8] = in[12+:8];
						imm[20+:12] = in[20+:12];
					end

				5'b11011: // jal
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd = in[7+:5];
						rs1 = '0;
						rs2 = '0;

						imm[0] = '0;
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[20];
						imm[12+:8] = in[12+:8];
						imm[20+:12] = {12{in[31]}};
					end

				default: ;
			endcase
		end
	end
endmodule
