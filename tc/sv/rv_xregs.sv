module rv_xregs #(
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
	bit[xlen - 1:0] registers[31:0];

	always @(posedge clock)
		if (reset)
			for (int i = 0; i < $size(registers); i++)
				registers[i[0+:$clog2($size(registers))]] <= '0;
		else if (rd != '0)
			registers[rd] <= rd_value;

	always_comb begin
		rs1_value = registers[rs1];
		rs2_value = registers[rs2];
	end
endmodule
