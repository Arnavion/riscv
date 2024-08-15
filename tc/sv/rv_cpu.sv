module rv_cpu (
	input bit clock,
	input bit reset,

	input bit[31:1] pc,
	input bit[31:0] inst,
	input logic[31:0] ram_load_value,

	output bit halt,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[31:2] ram_address,
	output logic[31:0] ram_store_value,
	output bit[31:1] pcnext
);
	wire[4:0] rd;
	wire[31:0] rd_store_value;
	wire[4:0] rs1;
	wire[4:0] rs2;
	wire[31:0] rs1_load_value;
	wire[31:0] rs2_load_value;
	rv_x_regs x_regs (
		.clock(clock), .reset(reset),
		.rd(rd), .rd_store_value(rd_store_value),
		.rs1(rs1), .rs2(rs2),
		.rs1_load_value(rs1_load_value), .rs2_load_value(rs2_load_value)
	);

	wire decompressor_sigill;
	wire decompressor_is_compressed;
	wire[31:0] decompressor_inst;
	rv_decompressor decompressor (
		.in(inst),
		.sigill(decompressor_sigill), .is_compressed(decompressor_is_compressed),
		.out(decompressor_inst)
	);

	wire decoder_sigill;
	wire[4:0] opcode;
	wire[2:0] funct3;
	wire[6:0] funct7;
	wire[31:0] imm;
	rv_decoder decoder (
		.in(decompressor_inst),
		.sigill(decoder_sigill),
		.rd(rd), .rs1(rs1), .rs2(rs2),
		.opcode(opcode), .funct3(funct3), .funct7(funct7),
		.imm(imm)
	);

	wire[31:0] ram_load_value_;
	wire[31:0] ram_store_value_;
	wire alu_sigill;
	wire[1:0] ram_address_lo;
	rv_alu alu (
		.opcode(opcode), .funct3(funct3), .funct7(funct7),
		.rs1(rs1_load_value), .rs2(rs2_load_value), .imm(imm),
		.pc(pc), .pcnext_in(pc + 31'(!decompressor_is_compressed) + 31'b1),
		.ram_load_value(ram_load_value_),
		.sigill(alu_sigill),
		.pcnext_out(pcnext),
		.rd(rd_store_value),
		.ram_load(ram_load), .ram_store(ram_store), .ram_funct3(ram_funct3), .ram_address({ram_address, ram_address_lo}), .ram_store_value(ram_store_value_)
	);

	wire efault;
	load_store load_store (
		.address(ram_address_lo),
		.funct3(funct3),
		.ram_load_value(ram_load_value),
		.store_value(ram_store_value_),
		.efault(efault),
		.load_value(ram_load_value_),
		.ram_store_value(ram_store_value)
	);

	assign halt = decompressor_sigill | decoder_sigill | alu_sigill | efault;
endmodule

`include "load_store.sv"
`include "rv_alu.sv"
`include "rv_decoder.sv"
`include "rv_decompressor.sv"
`include "rv_x_regs.sv"
