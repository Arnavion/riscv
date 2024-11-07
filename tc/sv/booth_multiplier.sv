/*
00 => P = (P    ) >> 1
01 => P = (P + A) >> 1
10 => P = (P - A) >> 1
11 => P = (P    ) >> 1


000 => P = ((P    ) >> 1    ) >> 1
001 => P = ((P + A) >> 1    ) >> 1
010 => P = ((P + A) >> 1    ) >> 1
011 => P = ((P    ) >> 1 + A) >> 1
100 => P = ((P    ) >> 1 - A) >> 1
101 => P = ((P - A) >> 1    ) >> 1
110 => P = ((P - A) >> 1    ) >> 1
111 => P = ((P    ) >> 1    ) >> 1
 */

module booth_multiplier #(
	parameter width = 64
) (
	input bit[width - 1:0] arg1,
	input bit arg1_is_signed,
	input bit[width - 1:0] arg2,
	input bit arg2_is_signed,

	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	bit signed[width + 1 - 1:0] a;

	bit signed[width + 1 - 1:0] r;

	bit signed[width + 2 + width + 1 - 1:0] p;

	always_comb begin
		a = signed'({arg1_is_signed & arg1[width - 1], arg1});

		r = signed'({arg2_is_signed & arg2[width - 1], arg2});

		p = signed'({
			signed'({(width + 1){r[0]}}) & -a,
			{(width + 2){1'bx}}
		}) >>> 2;

		for (int i = 0; i < $size(r) - 1; i += 2) begin
			if (& (r[i+:2] ^ {2{r[i + 2]}}))
				p >>>= 1;

			if (| (r[i+:2] ^ {2{r[i + 2]}}))
				p[width + 1+:width + 2] += unsigned'((width + 2)'(r[i + 2] ? -a : a));

			if (& (r[i+:2] ^ {2{r[i + 2]}}))
				p >>>= 1;
			else
				p >>>= 2;
		end

		mul = p[0+:width];
		mulh = p[width+:width];
	end
endmodule

`ifdef TESTING
module test_booth_multiplier;
	bit[64 - 1:0] arg1;
	bit arg1_is_signed;
	bit[64 - 1:0] arg2;
	bit arg2_is_signed;
	wire[64 - 1:0] mul;
	wire[64 - 1:0] mulh;
	booth_multiplier #(.width(64)) booth_multiplier_module (
		.arg1(arg1), .arg1_is_signed(arg1_is_signed),
		.arg2(arg2), .arg2_is_signed(arg2_is_signed),
		.mul(mul), .mulh(mulh)
	);

	task automatic test_case (
		input bit[64 - 1:0] arg1,
		input bit[64 - 1:0] arg2
	);
		test_case_inner(arg1, '0, arg2, '0);
		test_case_inner(arg1, '0, arg2, '1);
		test_case_inner(arg1, '1, arg2, '0);
		test_case_inner(arg1, '1, arg2, '1);
		test_case_inner(arg2, '0, arg1, '0);
		test_case_inner(arg2, '0, arg1, '1);
		test_case_inner(arg2, '1, arg1, '0);
		test_case_inner(arg2, '1, arg1, '1);
	endtask

	task automatic test_case_inner (
		input bit[64 - 1:0] arg1_,
		input bit arg1_is_signed_,
		input bit[64 - 1:0] arg2_,
		input bit arg2_is_signed_
	);
		bit[127:0] expected = unsigned'(
			(arg1_is_signed_ ? 128'(signed'(arg1_)) : signed'(128'(arg1_))) *
			(arg2_is_signed_ ? 128'(signed'(arg2_)) : signed'(128'(arg2_)))
		);
		bit[63:0] expected_mul = expected[0+:64];
		bit[63:0] expected_mulh = expected[64+:64];

		arg1 = arg1_;
		arg1_is_signed = arg1_is_signed_;
		arg2 = arg2_;
		arg2_is_signed = arg2_is_signed_;
		#1
		assert(mul == expected_mul) else $fatal(1, "0x%h *%s%s 0x%h = expected 0x%h got 0x%h", arg1_, arg1_is_signed_ ? "s" : "u", arg2_is_signed_ ? "s" : "u", arg2_, expected_mul, mul);
		assert(mulh == expected_mulh) else $fatal(1, "0x%h *%s%s 0x%h = expected 0x%h got 0x%h", arg1_, arg1_is_signed_ ? "s" : "u", arg2_is_signed_ ? "s" : "u", arg2_, expected_mulh, mulh);
	endtask

	initial begin
		test_case(64'h0000000000000000, 64'h0000000000000000);
		test_case(64'h0000000000000001, 64'h0000000000000001);
		test_case(64'hffffffffffffffff, 64'hffffffffffffffff);
		test_case(64'ha0b6b8129b5bdfd9, 64'hbcba1c1981093535);
		test_case(64'h2bc5ef4ad9b598c9, 64'he5f4626f4875716c);
		test_case(64'h0dfb92cdbf099338, 64'hefadab9de0fc1ded);
		test_case(64'hb82f30df91701f8c, 64'h106cbced76ae4c94);
		test_case(64'h6f683ce7c71964fd, 64'h34491aa4bdea1abb);
	end
endmodule
`endif
