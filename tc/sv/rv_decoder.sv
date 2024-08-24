module rv_decoder #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit[31:0] in,

	output bit sigill,
	output logic[31:0] rd_decoded,
	output logic[31:0] rs1_decoded,
	output logic[31:0] rs2_decoded,
	output logic[4:0] opcode,
	output logic[2:0] funct3,
	output logic[6:0] funct7,
	output logic[4:0] funct5,
	output logic[xlen - 1:0] imm
);
	logic rd_enable;
	reg_decoder rd_decoder (in[7+:5], rd_enable, rd_decoded);

	logic rs1_enable;
	reg_decoder rs1_decoder (in[15+:5], rs1_enable, rs1_decoded);

	logic rs2_enable;
	reg_decoder rs2_decoder (in[20+:5], rs2_enable, rs2_decoded);

	always_comb begin
		sigill = '1;
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		rd_enable = 'x;
		rs1_enable = 'x;
		rs2_enable = 'x;
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

						rd_enable = '1;
						rs1_enable = '1;
						rs2_enable = '1;
					end

				5'b00000, // load
				5'b001?0, // op-imm, op-imm-32
				5'b00111, // misc-mem
				5'b11001, // jalr
				5'b11100: // system
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '1;
						rs1_enable = '1;
						rs2_enable = '0;

						imm[0] = in[20];
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[31];
						imm[12+:8] = {8{in[31]}};
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

				5'b01000: // store
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '0;
						rs1_enable = '1;
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
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '0;
						rs1_enable = '1;
						rs2_enable = '1;

						imm[0] = '0;
						imm[1+:4] = in[8+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[7];
						imm[12+:8] = {8{in[31]}};
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

				5'b0?101: // auipc, lui
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '1;
						rs1_enable = '0;
						rs2_enable = '0;

						imm[0] = '0;
						imm[1+:4] = '0;
						imm[5+:6] = '0;
						imm[11] = '0;
						imm[12+:8] = in[12+:8];
						imm[20+:11] = in[20+:11];
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

				5'b11011: // jal
					begin
						sigill = '0;

						opcode = in[2+:5];
						funct3 = in[12+:3];
						funct7 = in[25+:7];
						funct5 = in[20+:5];

						rd_enable = '1;
						rs1_enable = '0;
						rs2_enable = '0;

						imm[0] = '0;
						imm[1+:4] = in[21+:4];
						imm[5+:6] = in[25+:6];
						imm[11] = in[20];
						imm[12+:8] = in[12+:8];
						imm[20+:11] = {11{in[31]}};
						imm[31+:xlen - 31] = {(xlen - 31){in[31]}};
					end

				default: ;
			endcase
		end
	end
endmodule

module reg_decoder (
	input bit[4:0] in,
	input bit enable,
	output bit[31:0] out
);
	assign out = enable ? 32'b1 << in : '0;
endmodule
