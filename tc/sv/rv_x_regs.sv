module rv_x_regs #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit clock,
	input bit reset,

	input bit[4:0] rd,
	input logic[xlen - 1:0] rd_value,
	input bit[4:0] rs1,
	input bit[4:0] rs2,

	output logic[xlen - 1:0] rs1_value,
	output logic[xlen - 1:0] rs2_value
);
	bit[xlen - 1:0] registers[32];

	assign rs1_value = registers[rs1];
	assign rs2_value = registers[rs2];

	always @(posedge clock) begin
		registers[rd] <= rd_value;

		// `registers[0]` causes the register indices to be inferred as 32-bit int,
		// which causes a JS error in digitaljs.
		//
		// `registers[5'b0]` infers the register indices correctly, but triggers a bug in yosys
		// where it redundantly generates assignments of `x` to the second half of registers.
		//
		// So use `registers[6'b0]` as a workaround.
		registers[($clog2($size(registers)) + 1)'('0)] <= '0;

		if (reset)
			for (int i = 1; i < $size(registers); i++)
				registers[i[0+:$clog2($size(registers))]] <= '0;
	end
endmodule
