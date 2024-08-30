module rv_cpu (
	input bit clock,
	input bit reset,

	input bit[63:1] pc,
	input bit[31:0] in,
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
	wire csrs_sigill;
	wire[63:0] csr_load_value;
	rv_csrs64 csrs (
		clock, reset,
		csr,
		csr_load,
		csr_store,
		csr_store_value,

		csrs_sigill,
		csr_load_value
	);

	wire decompressor_sigill;
	wire decompressor_is_compressed;
	wire[31:0] decompressor_inst;
	rv_decompressor #(.rv64(1)) decompressor (
		in,
		decompressor_sigill, decompressor_is_compressed,
		decompressor_inst
	);

	wire decoder_sigill;
	wire[4:0] opcode;
	wire[2:0] funct3;
	wire[6:0] funct7;
	wire[4:0] funct5;
	wire[31:0] imm;
	wire[4:0] csrimm;
	rv_decoder decoder (
		decompressor_inst,
		decoder_sigill,
		rd, rs1, rs2,
		csr, csr_load, csr_store,
		opcode, funct3, funct7, funct5,
		imm, csrimm
	);

	wire alu_sigill;
	rv_alu alu (
		opcode, funct3, funct7,
		rs1_load_value, rs2_load_value, imm, csrimm,
		pc, pc + 63'(!decompressor_is_compressed) + 63'b1,
		ram_load_value, csr_load_value,
		alu_sigill,
		pcnext,
		rd_store_value,
		ram_load, ram_store, ram_funct3, ram_address,
		csr_store_value
	);

	assign halt = csrs_sigill | decompressor_sigill | decoder_sigill | alu_sigill;
endmodule

`include "rv_alu.sv"
`include "rv_csrs64.sv"
`include "rv_decoder.sv"
`include "rv_decompressor.sv"
`include "rv_xregs.sv"
