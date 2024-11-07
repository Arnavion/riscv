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

module booth_multiplier_multi_cycle #(
	parameter width = 64,
	localparam i_width = $clog2(width / 2 + 1)
) (
	input bit clock,
	input bit reset,

	input bit start,
	input bit[width - 1:0] arg1,
	input bit arg1_is_signed,
	input bit[width - 1:0] arg2,
	input bit arg2_is_signed,

	output bit mulw_busy,
	output bit[width - 1:0] mulw,
	output bit mul_busy,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	bit[i_width - 1:0] i;

	bit[width + 2 + width + 1 - 1:0] p;
	bit[width + 2 + width + 1 - 1:0] next_p;

	multiplier_round #(.width(width)) multiplier_round_module (
		.arg1(arg1), .arg1_is_signed(arg1_is_signed),
		.arg2(arg2), .arg2_is_signed(arg2_is_signed),
		.first_round(i == '0), .p(p),
		.mulw(mulw), .mul(mul), .mulh(mulh),
		.next_p(next_p)
	);

	assign mulw_busy = start & (i < i_width'({1'b1, (i_width - 2)'('0)}));
	assign mul_busy = start & (i < {1'b1, (i_width - 1)'('0)});

	always_ff @(posedge clock) begin
		if (reset) begin
			i <= '0;
			p <= '0;
		end else begin
			i <= {i_width{mul_busy}} & (i + 1);
			p <= next_p;
		end
	end
endmodule

module multiplier_round #(
	parameter width = 64
) (
	input bit[width - 1:0] arg1,
	input bit arg1_is_signed,
	input bit[width - 1:0] arg2,
	input bit arg2_is_signed,

	input bit first_round,
	input bit[width + 2 + width + 1 - 1:0] p,

	output bit[width - 1:0] mulw,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh,
	output bit[width + 2 + width + 1 - 1:0] next_p
);
	bit[width - 1:0] next_p1;
	bit next_p2;
	bit[width - 1:0] next_p3;
	bit next_p4;
	bit next_p5;
	assign next_p = {next_p5, next_p4, next_p3, next_p2, next_p1};

	bit[width - 1:0] p2;

	bit p_sub;
	wire[width - 1:0] arg1_maybe_neg = arg1 ^ {width{p_sub}};
	//    ab ^ c = a(b ^ c) + a'c = a ? (b ^ c) : c
	// => arg1_sext = (arg1_is_signed & arg1[width - 1]) ^ p_sub = ...
	wire arg1_sext = arg1_is_signed ? arg1_maybe_neg[width - 1] : p_sub;
	wire[width + 2 - 1:0] p_plus;
	wire[width - 1:0] p_plus_inner_sum;
	wire p_plus_inner_cout;
	adder #(.width(width)) p_plus_inner_module (
		.cin(p_sub), .a(p2), .b(arg1_maybe_neg),
		.sum(p_plus_inner_sum), .cout(p_plus_inner_cout)
	);
	assign p_plus = {
		// {2{p2[width - 1]}} + {2{arg1_sext}} + 2'(p_plus_inner_cout)
		(p2[width - 1] & arg1_sext) |
			(p2[width - 1] & ~p_plus_inner_cout) |
			(arg1_sext & ~p_plus_inner_cout),
		p2[width - 1] ^ arg1_sext ^ p_plus_inner_cout,
		p_plus_inner_sum
	};

	always_comb begin
		mulw = 'x;
		mul = 'x;
		mulh = 'x;

		p_sub = 'x;
		p2 = 'x;

		if (first_round) begin
			next_p1 = arg2;
			next_p2 = arg2_is_signed & arg2[width - 1];

			unique case (arg2[0])
				1'b0: begin
					next_p3 = '0;
					next_p4 = '0;
					next_p5 = '0;
				end

				1'b1: begin
					p_sub = '1;
					p2 = '0;
					next_p3 = p_plus[0+:width];
					next_p4 = p_plus[width];
					next_p5 = p_plus[width + 1];
				end
			endcase

		end else begin
			next_p1 = p[2+:width];

			unique case (p[0+:2] ^ {2{p[2]}})
				2'b00: begin
					next_p2 = p[width + 2];
					next_p3 = p[width + 3+:width];
					next_p4 = p[width + width + 2];
					next_p5 = p[width + width + 2];
				end

				2'b01,
				2'b10: begin
					p_sub = p[2];
					p2 = p[width + 2+:width];
					next_p2 = p_plus[0];
					next_p3 = p_plus[1+:width];
					next_p4 = p_plus[width + 1];
					next_p5 = p_plus[width + 1];
				end

				2'b11: begin
					p_sub = p[2];
					p2 = p[width + 3+:width];
					next_p2 = p[width + 2];
					next_p3 = p_plus[0+:width];
					next_p4 = p_plus[width];
					next_p5 = p_plus[width + 1];
				end
			endcase

			mulw = {{(width / 2 + 1){next_p2}}, next_p1[width / 2 + 1+:width / 2 - 1]};
			mul = {next_p2, next_p1[1+:width - 1]};
			mulh = next_p3;
		end
	end
endmodule

module adder #(
	parameter width = 64
) (
	input bit cin,
	input bit[width - 1:0] a,
	input bit[width - 1:0] b,
	output bit[width -1:0] sum,
	output bit cout
);
	assign {cout, sum} = (width + 1)'(a) + (width + 1)'(b) + (width + 1)'(cin);
endmodule

`ifdef TESTING
module test_booth_multiplier_multi_cycle;
	bit clock;
	bit reset;
	bit start;
	bit[64 - 1:0] arg1;
	bit arg1_is_signed;
	bit[64 - 1:0] arg2;
	bit arg2_is_signed;
	wire mulw_busy;
	wire[64 - 1:0] mulw;
	wire mul_busy;
	wire[64 - 1:0] mul;
	wire[64 - 1:0] mulh;
	booth_multiplier_multi_cycle #(.width(64)) booth_multiplier_multi_cycle_module (
		.clock(clock), .reset(reset),
		.start(start),
		.arg1(arg1), .arg1_is_signed(arg1_is_signed),
		.arg2(arg2), .arg2_is_signed(arg2_is_signed),
		.mulw_busy(mulw_busy), .mulw(mulw),
		.mul_busy(mul_busy), .mul(mul), .mulh(mulh)
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
		bit[63:0] expected_mulw = unsigned'(64'(signed'(arg1_[0+:32] * arg2_[0+:32])));
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
		start = '1;
		#1
		assert(mulw_busy == '1) else $fatal;
		assert(mul_busy == '1) else $fatal;

		repeat (16) begin
			assert(mulw_busy == '1) else $fatal;
			clock = '1;
			#1
			clock = '0;
			#1;
		end
		assert(mulw_busy == '0) else $fatal;
		assert(mulw == expected_mulw) else $fatal;
		assert(mul_busy == '1) else $fatal;

		repeat (16) begin
			assert(mul_busy == '1) else $fatal;
			clock = '1;
			#1
			clock = '0;
			#1;
		end
		assert(mul_busy == '0) else $fatal;
		assert(mul == expected_mul) else $fatal;
		assert(mulh == expected_mulh) else $fatal;

		start = '0;
		#1
		clock = '1;
		#1
		clock = '0;
	endtask

	initial begin
		clock = '0;
		reset = '0;
		start = '0;
		arg1 = 64'h0000000000000000;
		arg1_is_signed = '0;
		arg2 = 64'h0000000000000000;
		arg2_is_signed = '0;

		reset = '1;
		#1
		clock = '1;
		#1
		reset = '0;
		#1
		clock = '0;
		#1

		assert(mulw_busy == '0) else $fatal;
		assert(mul_busy == '0) else $fatal;

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
