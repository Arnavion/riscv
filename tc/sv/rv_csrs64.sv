module rv_csrs64 (
	input bit clock,
	input bit reset,

	input logic[11:0] csr,
	input bit load,
	input bit store,
	input logic[63:0] store_value,

	output bit sigill,
	output logic[63:0] load_value
);
	bit[63:0] cycle;
	bit[63:0] time_;
	bit[63:0] instret;

	always_ff @(posedge clock)
		if (reset) begin
			cycle <= '0;
			time_ <= '0;
			instret <= '0;
		end else begin
			cycle <= cycle + 1;
			time_ <= time_ + 1000;
			instret <= instret + 64'b1;
		end

	always_comb begin
		sigill = '0;
		load_value = 'x;

		if (load) begin
			load_value = '0;
			unique0 case (csr)
				12'hc00: load_value = cycle;
				12'hc01: load_value = time_;
				12'hc02: load_value = instret;
				default: ;
			endcase
		end

		if (store)
			sigill = '1;
	end
endmodule
