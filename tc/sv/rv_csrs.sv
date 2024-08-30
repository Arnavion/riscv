module rv_csrs #(
	parameter rv64 = 1,
	localparam xlen = rv64 ? 64 : 32
) (
	input bit clock,
	input bit reset,

	input bit[63:0] time_,

	input logic[11:0] csr,
	input bit load,
	input bit store,
	input logic[xlen - 1:0] store_value,

	output bit sigill,
	output logic[xlen - 1:0] load_value
);
	bit[63:0] cycle;
	bit[63:0] instret;

	always_ff @(posedge clock)
		if (reset) begin
			cycle <= '0;
			instret <= '0;
		end else begin
			cycle <= cycle + 1;
			instret <= instret + 64'b1;
		end

	always_comb begin
		sigill = '0;
		load_value = 'x;

		if (load) begin
			load_value = '0;
			unique0 case (csr)
				12'h301: load_value = {
					rv64 ? 2'b10 : 2'b01, // XLEN
					{(xlen - 28){1'b0}},
					1'b0, // Reserved
					1'b0, // Reserved
					1'b0, // X
					1'b0, // Reserved
					1'b0, // V
					1'b0, // U
					1'b0, // Reserved
					1'b0, // S
					1'b0, // Reserved
					1'b0, // Q
					1'b0, // Reserved
					1'b0, // Reserved
					1'b0, // Reserved
					1'b0, // M
					1'b0, // Reserved
					1'b0, // Reserved
					1'b0, // Reserved
					1'b1, // I
					1'b0, // H
					1'b0, // Reserved
					1'b0, // F
					1'b0, // E
					1'b0, // D
					1'b1, // C
					1'b0, // B
					1'b0  // A
				};
				12'hc00: load_value = cycle[0+:xlen];
				12'hc01: load_value = time_[0+:xlen];
				12'hc02: load_value = instret[0+:xlen];
				12'hc80: if (!rv64) load_value[0+:32] = cycle[32+:32];
				12'hc81: if (!rv64) load_value[0+:32] = time_[32+:32];
				12'hc82: if (!rv64) load_value[0+:32] = instret[32+:32];
				default: ;
			endcase
		end

		if (store)
			sigill = '1;
	end
endmodule
