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
	input bit[width - 1:0] m,
	input bit m_is_signed,
	input bit[width - 1:0] r,
	input bit r_is_signed,

	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	bit[width + 2 - 1:0] a;
	assign a = {{2{m_is_signed & m[width - 1]}}, m};

	bit[width + 2 + width + 1 + 1 - 1:0] p;

	assign mul = p[1+:width];
	assign mulh = p[width + 1+:width];

	always_comb begin
		p = {{(width + 2){r[0]}} & -a, r_is_signed & r[width - 1], r, 1'b0};
		p = unsigned'(signed'(p) >>> 1);

		for (int i = 0; i < width; i += 2) begin
			unique case (p[0+:3])
				3'b000: begin
					p = unsigned'(signed'(p) >>> 2);
				end
				3'b001,
				3'b010: begin
					p[width + 1 + 1+:width + 2] += a;
					p = unsigned'(signed'(p) >>> 2);
				end
				3'b011: begin
					p = unsigned'(signed'(p) >>> 1);
					p[width + 1 + 1+:width + 2] += a;
					p = unsigned'(signed'(p) >>> 1);
				end
				3'b100: begin
					p = unsigned'(signed'(p) >>> 1);
					p[width + 1 + 1+:width + 2] -= a;
					p = unsigned'(signed'(p) >>> 1);
				end
				3'b101,
				3'b110: begin
					p[width + 1 + 1+:width + 2] -= a;
					p = unsigned'(signed'(p) >>> 2);
				end
				3'b111: begin
					p = unsigned'(signed'(p) >>> 2);
				end
			endcase
		end
	end
endmodule

`ifdef TESTING
module test_booth_multiplier;
	bit[64 - 1:0] m;
	bit m_is_signed;
	bit[64 - 1:0] r;
	bit r_is_signed;
	wire[64 - 1:0] mul;
	wire[64 - 1:0] mulh;
	booth_multiplier #(.width(64)) booth_multiplier_module (
		.m(m), .m_is_signed(m_is_signed),
		.r(r), .r_is_signed(r_is_signed),
		.mul(mul), .mulh(mulh)
	);

	`define test_case(m_, m_is_signed_, r_, r_is_signed_, expected_mul, expected_mulh) begin \
		m = m_; \
		m_is_signed = m_is_signed_; \
		r = r_; \
		r_is_signed = r_is_signed_; \
		#1 \
		assert(mul == expected_mul) else $fatal; \
		assert(mulh == expected_mulh) else $fatal; \
	end

	initial begin
		`test_case(64'h0000000000000000, '0, 64'h0000000000000000, '0, 64'h0000000000000000, 64'h0000000000000000)

		`test_case(64'h0000000000000001, '0, 64'h0000000000000001, '0, 64'h0000000000000001, 64'h0000000000000000)

		`test_case(64'hffffffffffffffff, '0, 64'hffffffffffffffff, '0, 64'h0000000000000001, 64'hfffffffffffffffe)
		`test_case(64'hffffffffffffffff, '0, 64'hffffffffffffffff, '1, 64'h0000000000000001, 64'hffffffffffffffff)
		`test_case(64'hffffffffffffffff, '1, 64'hffffffffffffffff, '0, 64'h0000000000000001, 64'hffffffffffffffff)
		`test_case(64'hffffffffffffffff, '1, 64'hffffffffffffffff, '1, 64'h0000000000000001, 64'h0000000000000000)

		`test_case(64'ha0b6b8129b5bdfd9, '0, 64'hbcba1c1981093535, '0, 64'h2aff503c66fe44ed, 64'h767b059366983688)
		`test_case(64'ha0b6b8129b5bdfd9, '0, 64'hbcba1c1981093535, '1, 64'h2aff503c66fe44ed, 64'hd5c44d80cb3c56af)
		`test_case(64'ha0b6b8129b5bdfd9, '1, 64'hbcba1c1981093535, '0, 64'h2aff503c66fe44ed, 64'hb9c0e979e58f0153)
		`test_case(64'ha0b6b8129b5bdfd9, '1, 64'hbcba1c1981093535, '1, 64'h2aff503c66fe44ed, 64'h190a31674a33217a)

		`test_case(64'hbcba1c1981093535, '0, 64'ha0b6b8129b5bdfd9, '0, 64'h2aff503c66fe44ed, 64'h767b059366983688)
		`test_case(64'hbcba1c1981093535, '0, 64'ha0b6b8129b5bdfd9, '1, 64'h2aff503c66fe44ed, 64'hb9c0e979e58f0153)
		`test_case(64'hbcba1c1981093535, '1, 64'ha0b6b8129b5bdfd9, '0, 64'h2aff503c66fe44ed, 64'hd5c44d80cb3c56af)
		`test_case(64'hbcba1c1981093535, '1, 64'ha0b6b8129b5bdfd9, '1, 64'h2aff503c66fe44ed, 64'h190a31674a33217a)
	end
endmodule
`endif
