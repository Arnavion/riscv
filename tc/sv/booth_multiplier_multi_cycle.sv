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
	output bit[width / 2 - 1:0] mulw,
	output bit mul_busy,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	bit[width + 1 + width + 1 + 1 - 1:0] p;
	bit[width + 1 + width + 1 + 1 - 1:0] next_p;

	bit[width + 1 + width + 1 + 1 - 1:0] p1;
	bit[width + 1 + width + 1 + 1 - 1:0] p2;

	bit p_sub;
	wire[width + 1 - 1:0] p_plus;
	adder #(.width(width + 1)) p_plus_module (p_sub, p2[width + 1 + 1+:width + 1], {m_is_signed & m[width - 1], m}, p_plus);

	wire[width + 1 + width + 1 + 1 - 1:0] p3 = {p_plus, p2[0+:width + 1 + 1]};

	bit[i_width - 1:0] i;
	bit[i_width - 1:0] next_i;

	assign mulw_busy = start & (i != unsigned'(i_width'(width / 4)));
	assign mul_busy = start & (i != unsigned'(i_width'(width / 2)));

	always_ff @(posedge clock) begin
		if (reset) begin
			p <= '0;
			i <= '0;
		end else begin
			p <= next_p;
			i <= next_i;
		end
	end

	always_comb begin
		mulw = 'x;
		mul = 'x;
		mulh = 'x;

		p_sub = 'x;

		if (!start) begin
			next_p = 'x;
			next_i = '0;
			p1 = 'x;
			p2 = 'x;

		end else begin
			if (i == '0) begin
				p1 = {{(width + 1){1'b0}}, r_is_signed & r[width - 1], r, 1'b0};

				unique case (p1[1])
					1'b0: begin
						p2 = 'x;
						next_p = unsigned'(signed'(p1) >>> 1);
					end
					1'b1: begin
						p_sub = '1;
						p2 = p1;
						next_p = unsigned'(signed'(p3) >>> 1);
					end
				endcase

			end else begin
				p1 = p;

				unique case (p1[0+:3])
					3'b000: begin
						p2 = 'x;
						next_p = unsigned'(signed'(p1) >>> 2);
					end
					3'b001,
					3'b010: begin
						p_sub = '0;
						p2 = p1;
						next_p = unsigned'(signed'(p3) >>> 2);
					end
					3'b011: begin
						p_sub = '0;
						p2 = unsigned'(signed'(p1) >>> 1);
						next_p = unsigned'(signed'(p3) >>> 1);
					end
					3'b100: begin
						p_sub = '1;
						p2 = unsigned'(signed'(p1) >>> 1);
						next_p = unsigned'(signed'(p3) >>> 1);
					end
					3'b101,
					3'b110: begin
						p_sub = '1;
						p2 = p1;
						next_p = unsigned'(signed'(p3) >>> 2);
					end
					3'b111: begin
						p2 = 'x;
						next_p = unsigned'(signed'(p1) >>> 2);
					end
				endcase

				if (i == unsigned'(i_width'(width / 4)))
					mulw = next_p[width / 2 + 1+:width / 2];
				if (i == unsigned'(i_width'(width / 2))) begin
					mul = next_p[0 + 1+:width];
					mulh = next_p[width + 1+:width];
				end
			end

			next_i = {i_width{(i != unsigned'(i_width'(width / 2)))}} & (i + 1);
		end
	end
endmodule

module adder #(
	parameter width = 1
) (
	input bit sub,
	input bit[width - 1:0] a,
	input bit[width - 1:0] b,

	output bit[width - 1:0] sum
);
	assign sum = a + (b ^ {width{sub}}) + width'(sub);
endmodule
