module rv_x_regs (
	input bit clock,
	input bit reset,

	input bit[4:0] rd,
	input logic[31:0] rd_store_value,
	input bit[4:0] rs1,
	input bit[4:0] rs2,

	output logic[31:0] rs1_load_value,
	output logic[31:0] rs2_load_value
);
	bit[31:0] registers[32];

	assign rs1_load_value = registers[rs1];
	assign rs2_load_value = registers[rs2];

	always @(posedge clock) begin
		if (| rd)
			registers[rd] <= rd_store_value;

		if (reset)
			foreach (registers[i])
				registers[i] <= '0;
	end
endmodule
