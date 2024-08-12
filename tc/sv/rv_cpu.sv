module rv_cpu (
	input bit clock,
	input bit reset,

	input bit[31:2] pc,
	input bit[31:0] in,
	input logic[31:0] ram_load_value,

	output bit halt,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[31:0] ram_address,
	output bit[31:2] pcnext
);
	wire[4:0] rd;
	wire[31:0] rd_store_value;
	wire[4:0] rs1;
	wire[4:0] rs2;
	wire[31:0] rs1_load_value;
	wire[31:0] rs2_load_value;
	rv_x_regs x_regs (
		.clock(clock), .reset(reset),
		.rd(rd), .rd_value(rd_store_value),
		.rs1(rs1), .rs2(rs2),
		.rs1_value(rs1_load_value), .rs2_value(rs2_load_value)
	);

	wire decoder_sigill;
	wire[4:0] opcode;
	wire[2:0] funct3;
	wire[6:0] funct7;
	wire[31:0] imm;
	rv_decoder decoder (
		.in(in),
		.sigill(decoder_sigill),
		.rd(rd), .rs1(rs1), .rs2(rs2),
		.opcode(opcode), .funct3(funct3), .funct7(funct7),
		.imm(imm)
	);

	wire alu_sigill;
	wire pcnext_lsb;
	rv_alu alu (
		.opcode(opcode), .funct3(funct3), .funct7(funct7),
		.rs1(rs1_load_value), .rs2(rs2_load_value), .imm(imm),
		.pc(pc), .pcnext_in(pc + 30'b1),
		.ram_load_value(ram_load_value),
		.sigill(alu_sigill),
		.pcnext_out({pcnext, pcnext_lsb}),
		.rd(rd_store_value),
		.ram_load(ram_load), .ram_store(ram_store), .ram_funct3(ram_funct3), .ram_address(ram_address)
	);

	assign halt = decoder_sigill | alu_sigill | pcnext_lsb;
endmodule

`include "rv_alu.sv"
`include "rv_decoder.sv"
`include "rv_x_regs.sv"
