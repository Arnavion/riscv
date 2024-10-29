module rv_cpu (
	input bit clock,
	input bit reset,

	input bit[63:1] pc,
	input bit[63:0] in,
	input logic[63:0] ram_load_value,

	output bit halt,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[63:0] ram_address,
	output bit[63:1] pcnext
);
	wire[4:0] rd;
	wire[63:0] rd_store_value;
	wire[4:0] rs1;
	wire[4:0] rs2;
	wire[63:0] rs1_load_value;
	wire[63:0] rs2_load_value;
	rv_xregs #(.rv64(1)) xregs (
		clock, reset,
		rd, rd_store_value,
		rs1, rs2,
		rs1_load_value, rs2_load_value
	);

	wire[11:0] csr;
	wire csr_load;
	wire csr_store;
	wire[63:0] csr_store_value;
	wire insts_num_minus_one;
	wire csrs_sigill;
	wire[63:0] csr_load_value;
	rv_csrs64 csrs (
		clock, reset,
		csr,
		csr_load,
		csr_store,
		csr_store_value,

		insts_num_minus_one,

		csrs_sigill,
		csr_load_value
	);

	wire decompressor1_sigill;
	wire decompressor1_is_compressed;
	wire[31:0] decompressor1_inst;
	rv_decompressor #(.rv64(1)) decompressor1 (
		in[0+:32],
		decompressor1_sigill, decompressor1_is_compressed,
		decompressor1_inst
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
		decompressor1_inst,
		decoder1_sigill,
		decoder1_rd, decoder1_rs1, decoder1_rs2,
		decoder1_csr, csr_load, csr_store,
		decoder1_opcode, decoder1_funct3, decoder1_funct7, decoder1_funct5,
		decoder1_imm, decoder1_csrimm
	);

	wire decompressor2_sigill;
	wire decompressor2_is_compressed;
	wire[31:0] decompressor2_inst;
	rv_decompressor #(.rv64(1)) decompressor2 (
		decompressor1_is_compressed ? in[16+:32] : in[32+:32],
		decompressor2_sigill, decompressor2_is_compressed,
		decompressor2_inst
	);

	wire decoder2_sigill;
	wire[4:0] decoder2_rd;
	wire[4:0] decoder2_rs1;
	wire[4:0] decoder2_rs2;
	wire[11:0] decoder2_csr;
	wire decoder2_csr_load;
	wire decoder2_csr_store;
	wire[4:0] decoder2_opcode;
	wire[2:0] decoder2_funct3;
	wire[6:0] decoder2_funct7;
	wire[4:0] decoder2_funct5;
	wire[31:0] decoder2_imm;
	wire[4:0] decoder2_csrimm;
	rv_decoder decoder2 (
		decompressor2_inst,
		decoder2_sigill,
		decoder2_rd, decoder2_rs1, decoder2_rs2,
		decoder2_csr, decoder2_csr_load, decoder2_csr_store,
		decoder2_opcode, decoder2_funct3, decoder2_funct7, decoder2_funct5,
		decoder2_imm, decoder2_csrimm
	);

	wire[1:0] insts_len_half_minus_one;
	wire[4:0] opcode;
	wire[2:0] funct3;
	wire[6:0] funct7;
	wire[4:0] funct5;
	wire[32:0] imm;
	wire[4:0] csrimm;
	rv_mop_fusion mop_fusion (
		decompressor1_is_compressed,
		decoder1_rd, decoder1_rs1, decoder1_rs2, decoder1_csr,
		decoder1_opcode, decoder1_funct3, decoder1_funct7, decoder1_funct5,
		decoder1_imm, decoder1_csrimm,

		~(decompressor2_sigill | decoder2_sigill), decompressor2_is_compressed,
		decoder2_rd, decoder2_rs1, decoder2_rs2,
		decoder2_opcode, decoder2_funct3, decoder2_funct7,
		decoder2_imm,

		insts_num_minus_one, insts_len_half_minus_one,

		rd, rs1, rs2, csr,
		opcode, funct3, funct7, funct5,
		imm, csrimm
	);

	wire alu_sigill;
	rv_alu alu (
		opcode, funct3, funct7, funct5,
		rs1_load_value, rs2_load_value, imm, csrimm,
		pc, pc + 63'(insts_len_half_minus_one) + 63'b1,
		ram_load_value, csr_load_value,
		alu_sigill,
		pcnext,
		rd_store_value,
		ram_load, ram_store, ram_funct3, ram_address,
		csr_store_value
	);

	assign halt = csrs_sigill | decompressor1_sigill | decoder1_sigill | alu_sigill;
endmodule

`include "rv_alu.sv"
`include "rv_csrs64.sv"
`include "rv_decoder.sv"
`include "rv_decompressor.sv"
`include "rv_mop_fusion.sv"
`include "rv_xregs.sv"
