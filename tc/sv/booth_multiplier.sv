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
	bit[width + 1 - 1:0] a;
	assign a = {m_is_signed & m[width - 1], m};

	bit[width + 1 + width + 1 + 1 - 1:0] p;

	assign mul = p[1+:width];
	assign mulh = p[width + 1+:width];

	always_comb begin
		p = {r[0] ? -a : {(width + 1){1'b0}}, r_is_signed & r[width - 1], r, 1'b0};
		p = unsigned'(signed'(p) >>> 1);

		for (int i = 0; i < width; i = i + 2) begin
			unique case (p[0+:3])
				3'b000: begin
					p = unsigned'(signed'(p) >>> 2);
				end
				3'b001,
				3'b010: begin
					p[width + 1 + 1+:width + 1] += a;
					p = unsigned'(signed'(p) >>> 2);
				end
				3'b011: begin
					p = unsigned'(signed'(p) >>> 1);
					p[width + 1 + 1+:width + 1] += a;
					p = unsigned'(signed'(p) >>> 1);
				end
				3'b100: begin
					p = unsigned'(signed'(p) >>> 1);
					p[width + 1 + 1+:width + 1] -= a;
					p = unsigned'(signed'(p) >>> 1);
				end
				3'b101,
				3'b110: begin
					p[width + 1 + 1+:width + 1] -= a;
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
		m, m_is_signed,
		r, r_is_signed,
		mul, mulh
	);

	initial begin
		m = 64'h0000000000000000;
		m_is_signed = '0;
		r = 64'h0000000000000000;
		r_is_signed = '0;
		#1
		assert(mulh == 64'h0000000000000000) else $fatal;
		assert(mul == 64'h0000000000000000) else $fatal;

		m = 64'h0000000000000001;
		m_is_signed = '0;
		r = 64'h0000000000000001;
		r_is_signed = '0;
		#1
		assert(mulh == 64'h0000000000000000) else $fatal;
		assert(mul == 64'h0000000000000001) else $fatal;

		m = 64'hffffffffffffffff;
		m_is_signed = '0;
		r = 64'hffffffffffffffff;
		r_is_signed = '0;
		#1
		assert(mulh == 64'hfffffffffffffffe) else $fatal;
		assert(mul == 64'h0000000000000001) else $fatal;

		m = 64'hffffffffffffffff;
		m_is_signed = '0;
		r = 64'hffffffffffffffff;
		r_is_signed = '1;
		#1
		assert(mulh == 64'hffffffffffffffff) else $fatal;
		assert(mul == 64'h0000000000000001) else $fatal;

		m = 64'hffffffffffffffff;
		m_is_signed = '1;
		r = 64'hffffffffffffffff;
		r_is_signed = '0;
		#1
		assert(mulh == 64'hffffffffffffffff) else $fatal;
		assert(mul == 64'h0000000000000001) else $fatal;

		m = 64'hffffffffffffffff;
		m_is_signed = '1;
		r = 64'hffffffffffffffff;
		r_is_signed = '1;
		#1
		assert(mulh == 64'h0000000000000000) else $fatal;
		assert(mul == 64'h0000000000000001) else $fatal;

		m = 64'ha0b6b8129b5bdfd9;
		m_is_signed = '0;
		r = 64'hbcba1c1981093535;
		r_is_signed = '0;
		#1
		assert(mulh == 64'h767b059366983688) else $fatal;
		assert(mul == 64'h2aff503c66fe44ed) else $fatal;

		m = 64'ha0b6b8129b5bdfd9;
		m_is_signed = '0;
		r = 64'hbcba1c1981093535;
		r_is_signed = '1;
		#1
		assert(mulh == 64'hd5c44d80cb3c56af) else $fatal;
		assert(mul == 64'h2aff503c66fe44ed) else $fatal;

		m = 64'ha0b6b8129b5bdfd9;
		m_is_signed = '1;
		r = 64'hbcba1c1981093535;
		r_is_signed = '0;
		#1
		assert(mulh == 64'hb9c0e979e58f0153) else $fatal;
		assert(mul == 64'h2aff503c66fe44ed) else $fatal;

		m = 64'ha0b6b8129b5bdfd9;
		m_is_signed = '1;
		r = 64'hbcba1c1981093535;
		r_is_signed = '1;
		#1
		assert(mulh == 64'h190a31674a33217a) else $fatal;
		assert(mul == 64'h2aff503c66fe44ed) else $fatal;
	end
endmodule
`endif
