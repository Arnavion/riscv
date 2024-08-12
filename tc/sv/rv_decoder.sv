module rv_decoder (
	input bit[31:0] in,

	output bit sigill,
	output logic[31:0] rd_decoded,
	output logic[31:0] rs1_decoded,
	output logic[31:0] rs2_decoded,
	output logic[4:0] opcode,
	output logic[2:0] funct3,
	output logic[6:0] funct7,
	output logic[4:0] funct5,
	output logic[31:0] imm
);
	typedef enum {
		InstructionType_R,
		InstructionType_I,
		InstructionType_S,
		InstructionType_B,
		InstructionType_U,
		InstructionType_J,
		InstructionType_Illegal
	} InstructionType;

	wire[31:0] rd_decoded_raw;
	reg_decoder rd_decoder (in[7+:5], rd_decoded_raw);

	wire[31:0] rs1_decoded_raw;
	reg_decoder rs1_decoder (in[15+:5], rs1_decoded_raw);

	wire[31:0] rs2_decoded_raw;
	reg_decoder rs2_decoder (in[20+:5], rs2_decoded_raw);

	InstructionType instruction_type;

	always_comb begin
		if (in[0+:2] == 2'b11) begin
			unique case (in[2+:5])
				5'b01100: // op
					instruction_type = InstructionType_R;

				5'b00000, // load
				5'b00100, // op-imm
				5'b00111, // misc-mem
				5'b11001, // jalr
				5'b11100: // system
					instruction_type = InstructionType_I;

				5'b01000: // store
					instruction_type = InstructionType_S;

				5'b11000: // branch
					instruction_type = InstructionType_B;

				5'b00101, // auipc
				5'b01101: // lui
					instruction_type = InstructionType_U;

				5'b11011: // jal
					instruction_type = InstructionType_J;

				default:
					instruction_type = InstructionType_Illegal;
			endcase
		end else
			instruction_type = InstructionType_Illegal;

		if (instruction_type == InstructionType_Illegal) begin
			sigill = '1;
			opcode = 'x;
			funct3 = 'x;
			funct7 = 'x;
			funct5 = 'x;
		end else begin
			sigill = '0;
			opcode = in[2+:5];
			funct3 = in[12+:3];
			funct7 = in[25+:7];
			funct5 = in[20+:5];
		end

		unique case (instruction_type)
			InstructionType_R,
			InstructionType_I,
			InstructionType_U,
			InstructionType_J:
				rd_decoded = rd_decoded_raw;

			InstructionType_S,
			InstructionType_B:
				rd_decoded = '0;

			InstructionType_Illegal:
				rd_decoded = 'x;
		endcase

		unique case (instruction_type)
			InstructionType_R,
			InstructionType_I,
			InstructionType_S,
			InstructionType_B:
				rs1_decoded = rs1_decoded_raw;

			InstructionType_U,
			InstructionType_J:
				rs1_decoded = '0;

			InstructionType_Illegal:
				rs1_decoded = 'x;
		endcase

		unique case (instruction_type)
			InstructionType_R,
			InstructionType_S,
			InstructionType_B:
				rs2_decoded = rs2_decoded_raw;

			InstructionType_I,
			InstructionType_U,
			InstructionType_J:
				rs2_decoded = '0;

			InstructionType_Illegal:
				rs2_decoded = 'x;
		endcase

		unique case (instruction_type)
			InstructionType_I:
				imm = {{20{in[31]}}, in[20+:12]};

			InstructionType_S:
				imm = {{20{in[31]}}, in[25+:7], in[7+:5]};

			InstructionType_B:
				imm = {{19{in[31]}}, in[31], in[7], in[25+:6], in[8+:4], 1'b0};

			InstructionType_U:
				imm = {in[12+:20], 12'b0};

			InstructionType_J:
				imm = {{11{in[31]}}, in[31], in[12+:8], in[20], in[21+:10], 1'b0};

			InstructionType_R,
			InstructionType_Illegal:
				imm = 'x;
		endcase
	end
endmodule

module reg_decoder (
	input bit[4:0] in,
	output bit[31:0] out
);
	assign out = 32'b1 << in;
endmodule
