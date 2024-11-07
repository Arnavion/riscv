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
	input bit[width - 1:0] m,
	input bit m_is_signed,
	input bit[width - 1:0] r,
	input bit r_is_signed,

	output bit mulw_busy,
	output bit[width - 1:0] mulw,
	output bit mul_busy,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	bit[i_width - 1:0] i;

	bit[width + 1 + width + 1 + 1 - 1:0] p;
	bit[width + 1 + width + 1 + 1 - 1:0] next_p;

	multiplier_round #(.width(width)) multiplier_round_module (
		.m(m), .m_is_signed(m_is_signed),
		.r(r), .r_is_signed(r_is_signed),
		.first_round(i == '0), .p(p),
		.mulw(mulw), .mul(mul), .mulh(mulh),
		.next_p(next_p)
	);

	assign mulw_busy = start & (i < i_width'({1'b1, {(i_width - 2){1'b0}}}));
	assign mul_busy = start & (i < {1'b1, {(i_width - 1){1'b0}}});

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
	input bit[width - 1:0] m,
	input bit m_is_signed,
	input bit[width - 1:0] r,
	input bit r_is_signed,

	input bit first_round,
	input bit[width + 1 + width + 1 + 1 - 1:0] p,

	output bit[width - 1:0] mulw,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh,
	output bit[width + 1 + width + 1 + 1 - 1:0] next_p
);
	bit[width - 1:0] next_p1;
	bit next_p2;
	bit[width - 1:0] next_p3;
	bit next_p4;
	bit next_p5;
	assign next_p = {next_p5, next_p4, next_p3, next_p2, next_p1};

	bit[width - 1:0] p2;

	bit p_sub;
	wire[width - 1:0] m_maybe_neg = m ^ {width{p_sub}};
	//    ab ^ c = a(b ^ c) + a'c = a ? (b ^ c) : c
	// => m_sext = (m_is_signed & m[width - 1]) ^ p_sub = ...
	wire m_sext = m_is_signed ? m_maybe_neg[width - 1] : p_sub;
	wire[width + 2 - 1:0] p_plus;
	wire[width - 1:0] p_plus_inner_sum;
	wire p_plus_inner_cout;
	adder #(.width(width)) p_plus_inner_module (
		.cin(p_sub), .a(p2), .b(m_maybe_neg),
		.sum(p_plus_inner_sum), .cout(p_plus_inner_cout)
	);
	assign p_plus = {
		// {2{p2[width - 1]}} + {2{m_sext}} + 2'(p_plus_inner_cout)
		(p2[width - 1] & m_sext) |
			(p2[width - 1] & ~p_plus_inner_cout) |
			(m_sext & ~p_plus_inner_cout),
		p2[width - 1] ^ m_sext ^ p_plus_inner_cout,
		p_plus_inner_sum
	};

	always_comb begin
		mulw = 'x;
		mul = 'x;
		mulh = 'x;

		p_sub = 'x;
		p2 = 'x;

		if (first_round) begin
			next_p1 = r;
			next_p2 = r_is_signed & r[width - 1];

			unique case (r[0])
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
	bit[64 - 1:0] m;
	bit m_is_signed;
	bit[64 - 1:0] r;
	bit r_is_signed;
	wire mulw_busy;
	wire[64 - 1:0] mulw;
	wire mul_busy;
	wire[64 - 1:0] mul;
	wire[64 - 1:0] mulh;
	booth_multiplier_multi_cycle #(.width(64)) booth_multiplier_multi_cycle_module (
		.clock(clock), .reset(reset),
		.start(start),
		.m(m), .m_is_signed(m_is_signed),
		.r(r), .r_is_signed(r_is_signed),
		.mulw_busy(mulw_busy), .mulw(mulw),
		.mul_busy(mul_busy), .mul(mul), .mulh(mulh)
	);

	task automatic test_case (
		input bit[64 - 1:0] m_,
		input bit m_is_signed_,
		input bit[64 - 1:0] r_,
		input bit r_is_signed_,
		input bit[64 - 1:0] expected_mulw,
		input bit[64 - 1:0] expected_mul,
		input bit[64 - 1:0] expected_mulh
	);
		m = m_;
		m_is_signed = m_is_signed_;
		r = r_;
		r_is_signed = r_is_signed_;
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
		m = 64'h0000000000000000;
		m_is_signed = '0;
		r = 64'h0000000000000000;
		r_is_signed = '0;

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

		test_case(64'h0000000000000000, '0, 64'h0000000000000000, '0, 64'h0000000000000000, 64'h0000000000000000, 64'h0000000000000000);

		test_case(64'h0000000000000001, '0, 64'h0000000000000001, '0, 64'h0000000000000001, 64'h0000000000000001, 64'h0000000000000000);

		test_case(64'hffffffffffffffff, '0, 64'hffffffffffffffff, '0, 64'h0000000000000001, 64'h0000000000000001, 64'hfffffffffffffffe);
		test_case(64'hffffffffffffffff, '0, 64'hffffffffffffffff, '1, 64'h0000000000000001, 64'h0000000000000001, 64'hffffffffffffffff);
		test_case(64'hffffffffffffffff, '1, 64'hffffffffffffffff, '0, 64'h0000000000000001, 64'h0000000000000001, 64'hffffffffffffffff);
		test_case(64'hffffffffffffffff, '1, 64'hffffffffffffffff, '1, 64'h0000000000000001, 64'h0000000000000001, 64'h0000000000000000);

		test_case(64'ha0b6b8129b5bdfd9, '0, 64'hbcba1c1981093535, '0, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'h767b059366983688);
		test_case(64'ha0b6b8129b5bdfd9, '0, 64'hbcba1c1981093535, '1, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'hd5c44d80cb3c56af);
		test_case(64'ha0b6b8129b5bdfd9, '1, 64'hbcba1c1981093535, '0, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'hb9c0e979e58f0153);
		test_case(64'ha0b6b8129b5bdfd9, '1, 64'hbcba1c1981093535, '1, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'h190a31674a33217a);

		test_case(64'hbcba1c1981093535, '0, 64'ha0b6b8129b5bdfd9, '0, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'h767b059366983688);
		test_case(64'hbcba1c1981093535, '0, 64'ha0b6b8129b5bdfd9, '1, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'hb9c0e979e58f0153);
		test_case(64'hbcba1c1981093535, '1, 64'ha0b6b8129b5bdfd9, '0, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'hd5c44d80cb3c56af);
		test_case(64'hbcba1c1981093535, '1, 64'ha0b6b8129b5bdfd9, '1, 64'h0000000066fe44ed, 64'h2aff503c66fe44ed, 64'h190a31674a33217a);
	end
endmodule
`endif
