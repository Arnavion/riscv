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
	bit[11:0] imm_31_20;
	bit[7:0] imm_19_12;
	bit imm_11;
	bit[5:0] imm_10_5;
	bit[3:0] imm_4_1;
	bit imm_0;
	assign imm = {imm_31_20, imm_19_12, imm_11, imm_10_5, imm_4_1, imm_0};
	function automatic void imm_(bit[31:0] imm);
		{imm_31_20, imm_19_12, imm_11, imm_10_5, imm_4_1, imm_0} = imm;
	endfunction

	always_comb begin
		sigill = ~& in[0+:2];
		opcode = 'x;
		funct3 = 'x;
		funct7 = 'x;
		funct5 = 'x;
		rd = 'x;
		rs1 = 'x;
		rs2 = 'x;
		imm_('x);

		if (~sigill) begin
			unique casez (in[2+:5])
				// op
				5'b01100: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];
					funct7 = in[25+:7];
					funct5 = in[20+:5];

					rd = in[7+:5];
					rs1 = in[15+:5];
					rs2 = in[20+:5];
				end

				// load
				5'b00000,
				// misc-mem
				5'b00011,
				// op-imm
				5'b00100,
				// jalr
				5'b11001: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];

					rd = in[7+:5];
					rs1 = in[15+:5];
					rs2 = '0;

					imm_(unsigned'(32'(signed'(in[20+:12]))));
				end

				// store
				5'b01000: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];
					funct7 = in[25+:7];
					funct5 = in[20+:5];

					rd = '0;
					rs1 = in[15+:5];
					rs2 = in[20+:5];

					imm_(unsigned'(32'(signed'({in[25+:7], in[7+:5]}))));
				end

				// branch
				5'b11000: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];
					funct7 = in[25+:7];
					funct5 = in[20+:5];

					rd = '0;
					rs1 = in[15+:5];
					rs2 = in[20+:5];

					imm_(unsigned'(32'(signed'({in[31], in[7], in[25+:6], in[8+:4], 1'b0}))));
				end

				// auipc, lui
				5'b0?101: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];
					funct7 = in[25+:7];
					funct5 = in[20+:5];

					rd = in[7+:5];
					rs1 = '0;
					rs2 = '0;

					imm_({in[12+:20], 12'b0});
				end

				// jal
				5'b11011: begin
					opcode = in[2+:5];
					funct3 = in[12+:3];
					funct7 = in[25+:7];
					funct5 = in[20+:5];

					rd = in[7+:5];
					rs1 = '0;
					rs2 = '0;

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

							rd = '0;
							rs1 = '0;
							rs2 = '0;
						end

						default: begin
							sigill = '1;

							opcode = 'x;
							funct3 = 'x;
						end
					endcase
				end

				default:
					sigill = '1;
			endcase
		end
	end
endmodule
