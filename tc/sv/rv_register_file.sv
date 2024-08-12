module rv_register_file (
	input bit clock,

	input bit[4:0] rd,
	input logic[31:0] rd_value,
	input bit[4:0] rs1,
	input bit[4:0] rs2,

	output logic [31:0] rs1_value,
	output logic [31:0] rs2_value
);
	bit[31:0] registers[31:0];

	initial
		for (int i = 0; i <= 32; i++)
			registers[i] = '0;

	always @(posedge clock)
		if (rd != '0)
			registers[rd] <= rd_value;

	always_comb begin
		rs1_value = registers[rs1];
		rs2_value = registers[rs2];
	end
endmodule
