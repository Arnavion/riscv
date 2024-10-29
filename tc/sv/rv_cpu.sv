module rv_cpu (
	input bit clock,
	input bit reset,

	input bit[63:0] csr_time,

	input bit[63:1] pc,
	input bit[63:0] inst,
	input logic[63:0] ram_load_value,

	output bit halt,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[63:3] ram_address,
	output logic[63:0] ram_store_value,
	output bit[63:1] pcnext
);
	wire[4:0] rd;
	wire[63:0] rd_store_value;
	wire[4:0] rs1;
	wire[4:0] rs2;
	wire[63:0] rs1_load_value;
	wire[63:0] rs2_load_value;
	rv_x_regs #(.rv64(1)) x_regs (
		.clock(clock), .reset(reset),
		.rd(rd), .rd_store_value(rd_store_value),
		.rs1(rs1), .rs2(rs2),
		.rs1_load_value(rs1_load_value), .rs2_load_value(rs2_load_value)
	);

	wire[11:0] csr;
	wire csr_load;
	wire csr_store;
	wire[63:0] csr_store_value;
	wire insts_num_minus_one;
	wire csrs_sigill;
	wire[63:0] csr_load_value;
	rv_csrs #(.rv64(1)) csrs (
		.clock(clock), .reset(reset),
		.time_(csr_time),
		.csr(csr),
		.load(csr_load),
		.store(csr_store),
		.store_value(csr_store_value),
		.insts_num_minus_one(insts_num_minus_one),
		.sigill(csrs_sigill),
		.load_value(csr_load_value)
	);

	wire decompressor1_sigill;
	wire decompressor1_is_compressed;
	wire[31:0] decompressor1_inst;
	rv_decompressor #(.rv64(1)) decompressor1 (
		.in(inst[0+:32]),
		.sigill(decompressor1_sigill), .is_compressed(decompressor1_is_compressed),
		.out(decompressor1_inst)
	);

	wire decoder1_sigill;
	wire[4:0] decoder1_rd;
	wire[4:0] decoder1_rs1;
	wire[4:0] decoder1_rs2;
	wire[11:0] decoder1_csr;
	wire[4:0] decoder1_opcode;
	wire[2:0] decoder1_funct3;
	wire[6:0] decoder1_funct7;
	wire[4:0] decoder1_funct5;
	wire[31:0] decoder1_imm;
	wire[4:0] decoder1_csrimm;
	rv_decoder decoder1 (
		.in(decompressor1_inst),
		.sigill(decoder1_sigill),
		.rd(decoder1_rd), .rs1(decoder1_rs1), .rs2(decoder1_rs2),
		.csr(decoder1_csr), .csr_load(csr_load), .csr_store(csr_store),
		.opcode(decoder1_opcode), .funct3(decoder1_funct3), .funct7(decoder1_funct7), .funct5(decoder1_funct5),
		.imm(decoder1_imm), .csrimm(decoder1_csrimm)
	);

	wire decompressor2_sigill;
	wire decompressor2_is_compressed;
	wire[31:0] decompressor2_inst;
	rv_decompressor #(.rv64(1)) decompressor2 (
		.in(decompressor1_is_compressed ? inst[16+:32] : inst[32+:32]),
		.sigill(decompressor2_sigill), .is_compressed(decompressor2_is_compressed),
		.out(decompressor2_inst)
	);

	wire decoder2_sigill;
	wire[4:0] decoder2_rd;
	wire[4:0] decoder2_rs1;
	wire[4:0] decoder2_rs2;
	wire[4:0] decoder2_opcode;
	wire[2:0] decoder2_funct3;
	wire[6:0] decoder2_funct7;
	wire[31:0] decoder2_imm;
	rv_decoder decoder2 (
		.in(decompressor2_inst),
		.sigill(decoder2_sigill),
		.rd(decoder2_rd), .rs1(decoder2_rs1), .rs2(decoder2_rs2),
		.opcode(decoder2_opcode), .funct3(decoder2_funct3), .funct7(decoder2_funct7),
		.imm(decoder2_imm)
	);

	wire[1:0] insts_len_half_minus_one;
	wire[4:0] opcode;
	wire[2:0] funct3;
	wire[6:0] funct7;
	wire[4:0] funct5;
	wire[32:0] imm;
	wire[4:0] csrimm;
	rv_mop_fusion mop_fusion (
		.a_is_compressed(decompressor1_is_compressed),
		.a_rd(decoder1_rd), .a_rs1(decoder1_rs1), .a_rs2(decoder1_rs2), .a_csr(decoder1_csr),
		.a_opcode(decoder1_opcode), .a_funct3(decoder1_funct3), .a_funct7(decoder1_funct7), .a_funct5(decoder1_funct5),
		.a_imm(decoder1_imm), .a_csrimm(decoder1_csrimm),

		.b_is_valid(~(decompressor2_sigill | decoder2_sigill)), .b_is_compressed(decompressor2_is_compressed),
		.b_rd(decoder2_rd), .b_rs1(decoder2_rs1), .b_rs2(decoder2_rs2),
		.b_opcode(decoder2_opcode), .b_funct3(decoder2_funct3), .b_funct7(decoder2_funct7),
		.b_imm(decoder2_imm),

		.insts_num_minus_one(insts_num_minus_one), .insts_len_half_minus_one(insts_len_half_minus_one),

		.rd(rd), .rs1(rs1), .rs2(rs2), .csr(csr),
		.opcode(opcode), .funct3(funct3), .funct7(funct7), .funct5(funct5),
		.imm(imm), .csrimm(csrimm)
	);

	wire[63:0] ram_load_value_;
	wire[63:0] ram_store_value_;
	wire alu_sigill;
	wire[2:0] ram_address_lo;
	rv_alu alu (
		.opcode(opcode), .funct3(funct3), .funct7(funct7), .funct5(funct5),
		.rs1(rs1_load_value), .rs2(rs2_load_value), .imm_(imm), .csrimm_(csrimm),
		.pc(pc), .pcnext_in(pc + 63'(insts_len_half_minus_one) + 63'b1),
		.ram_load_value(ram_load_value_), .csr_load_value(csr_load_value),
		.sigill(alu_sigill),
		.pcnext_out(pcnext),
		.rd(rd_store_value),
		.ram_load(ram_load), .ram_store(ram_store), .ram_funct3(ram_funct3), .ram_address({ram_address, ram_address_lo}), .ram_store_value(ram_store_value_),
		.csr_store_value(csr_store_value)
	);

	wire efault;
	load_store64 load_store64 (
		.address(ram_address_lo),
		.funct3(funct3),
		.ram_load_value(ram_load_value),
		.store_value(ram_store_value_),
		.efault(efault),
		.load_value(ram_load_value_),
		.ram_store_value(ram_store_value)
	);

	assign halt = csrs_sigill | decompressor1_sigill | decoder1_sigill | alu_sigill | efault;
endmodule

`include "load_store64.sv"
`include "rv_alu.sv"
`include "rv_csrs.sv"
`include "rv_decoder.sv"
`include "rv_decompressor.sv"
`include "rv_mop_fusion.sv"
`include "rv_x_regs.sv"
