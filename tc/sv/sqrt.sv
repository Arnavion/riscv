module sqrt #(
	parameter width = 32
) (
	input bit[width - 1:0] n,
	output bit[width / 2 - 1:0] isqrt,
	output bit[width - 1:0] fsqrt
);
	bit[width + 2 + width - 2 - 1:0] a;
	bit[width - 1:0] r;
	bit a_upper_next_sign;
	bit[width:0] a_upper_next;

	always_comb begin
		a = $size(a)'(n);
		r = '1;

		for (int i = 0; i < width; i++) begin
			{a_upper_next_sign, a_upper_next} = a[width - 2+:width + 2] + {r, 2'b11};
			r = {r[0+:width - 1], a_upper_next_sign};
			a = {
				a_upper_next_sign ? a[width - 2+:width] : a_upper_next[0+:width],
				a[0+:width - 2],
				2'b00
			};

			if (i == width / 2 - 1)
				isqrt = ~r[0+:width / 2];
		end

		fsqrt = {isqrt, ~r[0+:width / 2]};
	end
endmodule

`ifdef TESTING
module test_sqrt;
	bit[15:0] n;
	wire[7:0] isqrt;
	wire[15:0] fsqrt;
	sqrt #(.width(16)) sqrt_module (n, isqrt, fsqrt);

	task automatic test_case (
		input bit[15:0] n_,
		input bit[15:0] expected_fsqrt
	);
		n = n_;
		#1
		assert(isqrt == expected_fsqrt[8+:8]) else $fatal(1, "sqrt(0x%h) = expected 0x%h got 0x%h", n, expected_fsqrt[8+:8], isqrt);
		assert(fsqrt == expected_fsqrt) else $fatal(1, "sqrt(0x%h) = expected 0x%h got 0x%h", n, expected_fsqrt, fsqrt);
	endtask

	real expected_fsqrt;

	initial begin
		for (real n_ = 16'h0000; n_ <= 16'hffff; n_++) begin
			expected_fsqrt = $sqrt(n_) * 256;
			test_case($rtoi(n_), $rtoi(expected_fsqrt));
		end
	end
endmodule
`endif
