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
	localparam i_width = $clog2(width + 1)
) (
	input bit clock,
	input bit start,
	input bit[width - 1:0] m,
	input bit m_is_signed,
	input bit[width - 1:0] r,
	input bit r_is_signed,

	output bit busy,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	bit[width + 1 - 1:0] a;
	assign a = {m_is_signed ? m[width - 1] : 1'b0, m};

	bit[width + 1 + width + 1 + 1 - 1:0] p;
	bit[width + 1 + width + 1 + 1 - 1:0] next_p;

	bit[width + 1 + width + 1 + 1 - 1:0] p1;
	bit[width + 1 + width + 1 + 1 - 1:0] p2;
	bit[width + 1 + width + 1 + 1 - 1:0] p3;

	bit[width + 1 - 1:0] p_addend;
	bit p_add_carry;
	wire[width + 1 - 1:0] p_plus;
	adder #(.width(width + 1)) p_plus_module (p_add_carry, p2[width + 1 + 1+:width + 1], p_addend, p_plus);

	bit[i_width - 1:0] i = i_width'(-1);
	bit[i_width - 1:0] next_i;

	bit i_plus_one;
	bit i_plus_two;
	bit[i_width - 1:0] next_i_counter;
	counter #(.width(i_width)) counter_module (i, i_plus_one, i_plus_two, next_i_counter);

	assign busy = start && (signed'(next_i) != width);
	assign mul = next_p[1+:width];
	assign mulh = next_p[width + 1+:width];

	always_ff @(posedge clock) begin
		p <= next_p;
		i <= next_i;
	end

	always_comb begin
		p_addend = 'x;
		p_add_carry = 'x;

		if (!start || signed'(i) == width) begin
			next_p = 'x;
			i_plus_one = 'x;
			i_plus_two = 'x;
			next_i = i_width'(-1);
			p1 = 'x;
			p2 = 'x;
			p3 = 'x;
		end else begin
			p1 = (signed'(i) == -1) ?
				{{(width + 1){1'b0}}, r_is_signed ? r[width - 1] : 1'b0, r, 1'b0} :
				p;

			if (signed'(i) <= width - 2) begin
				unique case (p1[0+:3])
					3'b000: begin
						p2 = 'x;
						p3 = p1;
						next_p = unsigned'(signed'(p3) >>> 2);
					end
					3'b001,
					3'b010: begin
						p2 = p1;
						p_addend = a;
						p_add_carry = '0;
						p3 = {p_plus, p2[0+:width + 1 + 1]};
						next_p = unsigned'(signed'(p3) >>> 2);
					end
					3'b011: begin
						p2 = unsigned'(signed'(p1) >>> 1);
						p_addend = a;
						p_add_carry = '0;
						p3 = {p_plus, p2[0+:width + 1 + 1]};
						next_p = unsigned'(signed'(p3) >>> 1);
					end
					3'b100: begin
						p2 = unsigned'(signed'(p1) >>> 1);
						p_addend = ~a;
						p_add_carry = '1;
						p3 = {p_plus, p2[0+:width + 1 + 1]};
						next_p = unsigned'(signed'(p3) >>> 1);
					end
					3'b101,
					3'b110: begin
						p2 = p1;
						p_addend = ~a;
						p_add_carry = '1;
						p3 = {p_plus, p2[0+:width + 1 + 1]};
						next_p = unsigned'(signed'(p3) >>> 2);
					end
					3'b111: begin
						p2 = 'x;
						p3 = p1;
						next_p = unsigned'(signed'(p3) >>> 2);
					end
				endcase

				i_plus_one = '0;
				i_plus_two = '1;
				next_i = next_i_counter;

			end else begin
				unique case (p1[0+:2])
					2'b00: begin
						p2 = 'x;
						p3 = p1;
					end
					2'b01: begin
						p2 = p1;
						p_addend = a;
						p_add_carry = '0;
						p3 = {p_plus, p2[0+:width + 1 + 1]};
					end
					2'b10: begin
						p2 = p1;
						p_addend = ~a;
						p_add_carry = '1;
						p3 = {p_plus, p2[0+:width + 1 + 1]};
					end
					2'b11: begin
						p2 = 'x;
						p3 = p1;
					end
				endcase
				next_p = unsigned'(signed'(p3) >>> 1);

				i_plus_one = '1;
				i_plus_two = '0;
				next_i = next_i_counter;
			end
		end
	end
endmodule

module adder #(
	parameter width
) (
	input bit cin,
	input bit[width - 1:0] a,
	input bit[width - 1:0] b,

	output bit[width - 1:0] sum
);
	assign sum = a + b + width'(cin);
endmodule

module counter #(
	parameter width
) (
	input bit[width - 1:0] i,
	input bit add_one,
	input bit add_two,

	output bit[width - 1:0] next_i
);
	assign next_i = i + (add_one ? 1 : 0) + (add_two ? 2 : 0);
endmodule
