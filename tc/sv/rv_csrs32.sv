module rv_csrs32 (
	input bit clock,
	input bit reset,

	input logic[11:0] csr,
	input bit csr_load,
	input bit csr_store,
	input logic[31:0] csr_store_value,

	output bit sigill,
	output logic[31:0] csr_load_value
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
		csr_load_value = 'x;

		if (csr_load) begin
			csr_load_value = '0;
			unique0 case (csr)
				12'hc00: csr_load_value = cycle[0+:32];
				12'hc01: csr_load_value = time_[0+:32];
				12'hc02: csr_load_value = instret[0+:32];
				12'hc80: csr_load_value = cycle[32+:32];
				12'hc81: csr_load_value = time_[32+:32];
				12'hc82: csr_load_value = instret[32+:32];
				default: ;
			endcase
		end

		if (csr_store)
			sigill = '1;
	end
endmodule
