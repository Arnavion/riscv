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
	assign a = {m_is_signed ? m[width - 1] : 1'b0, m};

	bit[width + 1 + width + 1 + 1 - 1:0] p;

	assign mul = p[1+:width];
	assign mulh = p[width + 1+:width];

	always_comb begin
		p = {{(width + 1){1'b0}}, r_is_signed ? r[width - 1] : 1'b0, r, 1'b0};

		for (int i = -1; i < width; i = i + 2) begin
			if (i < width - 1) begin
				unique case (p[0+:3])
					3'b000: begin
						p = unsigned'(signed'(p) >>> 2);
					end
					3'b001,
					3'b010: begin
						p[1 + width + 1+:width + 1] = p[1 + width + 1+:width + 1] + a;
						p = unsigned'(signed'(p) >>> 2);
					end
					3'b011: begin
						p = unsigned'(signed'(p) >>> 1);
						p[1 + width + 1+:width + 1] = p[1 + width + 1+:width + 1] + a;
						p = unsigned'(signed'(p) >>> 1);
					end
					3'b100: begin
						p = unsigned'(signed'(p) >>> 1);
						p[1 + width + 1+:width + 1] = p[1 + width + 1+:width + 1] - a;
						p = unsigned'(signed'(p) >>> 1);
					end
					3'b101,
					3'b110: begin
						p[1 + width + 1+:width + 1] = p[1 + width + 1+:width + 1] - a;
						p = unsigned'(signed'(p) >>> 2);
					end
					3'b111: begin
						p = unsigned'(signed'(p) >>> 2);
					end
				endcase
			end else begin
				unique case (p[0+:2])
					2'b00: ;
					2'b01: p[1 + width + 1+:width + 1] = p[1 + width + 1+:width + 1] + a;
					2'b10: p[1 + width + 1+:width + 1] = p[1 + width + 1+:width + 1] - a;
					2'b11: ;
				endcase
				p = unsigned'(signed'(p) >>> 1);
			end
		end
	end
endmodule
