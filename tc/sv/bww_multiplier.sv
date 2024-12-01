module bww_multiplier (
	input bit[7:0] a,
	input bit a_is_signed,
	input bit[7:0] b,
	input bit b_is_signed,

	output bit[7:0] mul,
	output bit[7:0] mulh
);
	wire s0, c0;
	half_adder adder0(.a(a[0] & b[1]), .b(a[1] & b[0]), .sum(s0), .carry(c0));
	wire s1, c1;
	full_adder adder1 (.a(a[0] & b[2]), .b(a[1] & b[1]), .c(a[2] & b[0]), .sum(s1), .carry(c1));
	wire s2, c2;
	half_adder adder2(.a(c0), .b(s1), .sum(s2), .carry(c2));
	wire s3, c3;
	full_adder adder3 (.a(a[0] & b[3]), .b(a[1] & b[2]), .c(a[2] & b[1]), .sum(s3), .carry(c3));
	wire s4, c4;
	full_adder adder4 (.a(a[3] & b[0]), .b(c1), .c(s3), .sum(s4), .carry(c4));
	wire s5, c5;
	half_adder adder5(.a(c2), .b(s4), .sum(s5), .carry(c5));
	wire s6, c6;
	full_adder adder6 (.a(a[0] & b[4]), .b(a[1] & b[3]), .c(a[2] & b[2]), .sum(s6), .carry(c6));
	wire s7, c7;
	full_adder adder7 (.a(a[3] & b[1]), .b(a[4] & b[0]), .c(c3), .sum(s7), .carry(c7));
	wire s8, c8;
	full_adder adder8 (.a(s6), .b(s7), .c(c4), .sum(s8), .carry(c8));
	wire s9, c9;
	half_adder adder9(.a(c5), .b(s8), .sum(s9), .carry(c9));
	wire s10, c10;
	full_adder adder10 (.a(a[0] & b[5]), .b(a[1] & b[4]), .c(a[2] & b[3]), .sum(s10), .carry(c10));
	wire s11, c11;
	full_adder adder11 (.a(a[3] & b[2]), .b(a[4] & b[1]), .c(a[5] & b[0]), .sum(s11), .carry(c11));
	wire s12, c12;
	full_adder adder12 (.a(c6), .b(s10), .c(s11), .sum(s12), .carry(c12));
	wire s13, c13;
	full_adder adder13 (.a(c7), .b(c8), .c(s12), .sum(s13), .carry(c13));
	wire s14, c14;
	half_adder adder14(.a(c9), .b(s13), .sum(s14), .carry(c14));
	wire s15, c15;
	full_adder adder15 (.a(a[0] & b[6]), .b(a[1] & b[5]), .c(a[2] & b[4]), .sum(s15), .carry(c15));
	wire s16, c16;
	full_adder adder16 (.a(a[3] & b[3]), .b(a[4] & b[2]), .c(a[5] & b[1]), .sum(s16), .carry(c16));
	wire s17, c17;
	full_adder adder17 (.a(a[6] & b[0]), .b(c10), .c(c11), .sum(s17), .carry(c17));
	wire s18, c18;
	full_adder adder18 (.a(s15), .b(s16), .c(c12), .sum(s18), .carry(c18));
	wire s19, c19;
	full_adder adder19 (.a(s17), .b(s18), .c(c13), .sum(s19), .carry(c19));
	wire s20, c20;
	half_adder adder20(.a(c14), .b(s19), .sum(s20), .carry(c20));
	wire s21, c21;
	full_adder adder21 (.a(a[0] & b[7]), .b(a[1] & b[6]), .c(a[2] & b[5]), .sum(s21), .carry(c21));
	wire s22, c22;
	full_adder adder22 (.a(a[3] & b[4]), .b(a[4] & b[3]), .c(a[5] & b[2]), .sum(s22), .carry(c22));
	wire s23, c23;
	full_adder adder23 (.a(a[6] & b[1]), .b(a[7] & b[0]), .c(c15), .sum(s23), .carry(c23));
	wire s24, c24;
	full_adder adder24 (.a(c16), .b(s21), .c(s22), .sum(s24), .carry(c24));
	wire s25, c25;
	full_adder adder25 (.a(s23), .b(c17), .c(s24), .sum(s25), .carry(c25));
	wire s26, c26;
	full_adder adder26 (.a(c18), .b(s25), .c(c19), .sum(s26), .carry(c26));
	wire s27, c27;
	half_adder adder27(.a(c20), .b(s26), .sum(s27), .carry(c27));
	wire s28, c28;
	full_adder adder28 (.a(a[1] & b[7]), .b(a[2] & b[6]), .c(a[3] & b[5]), .sum(s28), .carry(c28));
	wire s29, c29;
	full_adder adder29 (.a(a[4] & b[4]), .b(a[5] & b[3]), .c(a[6] & b[2]), .sum(s29), .carry(c29));
	wire s30, c30;
	full_adder adder30 (.a(a[7] & b[1]), .b(~(a[0] & b[7] & b_is_signed)), .c(~(a[7] & a_is_signed & b[0])), .sum(s30), .carry(c30));
	wire s31, c31;
	full_adder adder31 (.a(c21), .b(c22), .c(s28), .sum(s31), .carry(c31));
	wire s32, c32;
	full_adder adder32 (.a(s29), .b(c23), .c(s30), .sum(s32), .carry(c32));
	wire s33, c33;
	full_adder adder33 (.a(c24), .b(s31), .c(s32), .sum(s33), .carry(c33));
	wire s34, c34;
	full_adder adder34 (.a(c25), .b(s33), .c(c26), .sum(s34), .carry(c34));
	wire s35, c35;
	half_adder adder35(.a(c27), .b(s34), .sum(s35), .carry(c35));
	wire s36, c36;
	full_adder adder36 (.a(a[2] & b[7]), .b(a[3] & b[6]), .c(a[4] & b[5]), .sum(s36), .carry(c36));
	wire s37, c37;
	full_adder adder37 (.a(a[5] & b[4]), .b(a[6] & b[3]), .c(a[7] & b[2]), .sum(s37), .carry(c37));
	wire s38, c38;
	full_adder adder38 (.a(~(a[1] & b[7] & b_is_signed)), .b(~(a[7] & a_is_signed & b[1])), .c(c28), .sum(s38), .carry(c38));
	wire s39, c39;
	full_adder adder39 (.a(c29), .b(c30), .c(s36), .sum(s39), .carry(c39));
	wire s40, c40;
	full_adder adder40 (.a(s37), .b(s38), .c(c31), .sum(s40), .carry(c40));
	wire s41, c41;
	full_adder adder41 (.a(c32), .b(s39), .c(s40), .sum(s41), .carry(c41));
	wire s42, c42;
	full_adder adder42 (.a(c33), .b(s41), .c(c34), .sum(s42), .carry(c42));
	wire s43, c43;
	half_adder_plus_one adder43 (.a(c35), .b(s42), .sum(s43), .carry(c43));
	wire s44, c44;
	full_adder adder44 (.a(a[3] & b[7]), .b(a[4] & b[6]), .c(a[5] & b[5]), .sum(s44), .carry(c44));
	wire s45, c45;
	full_adder adder45 (.a(a[6] & b[4]), .b(a[7] & b[3]), .c(~(a[2] & b[7] & b_is_signed)), .sum(s45), .carry(c45));
	wire s46, c46;
	full_adder adder46 (.a(~(a[7] & a_is_signed & b[2])), .b(c36), .c(c37), .sum(s46), .carry(c46));
	wire s47, c47;
	full_adder adder47 (.a(s44), .b(s45), .c(c38), .sum(s47), .carry(c47));
	wire s48, c48;
	full_adder adder48 (.a(c39), .b(s46), .c(c40), .sum(s48), .carry(c48));
	wire s49, c49;
	full_adder adder49 (.a(s47), .b(c41), .c(s48), .sum(s49), .carry(c49));
	wire s50, c50;
	full_adder adder50 (.a(s49), .b(c42), .c(c43), .sum(s50), .carry(c50));
	wire s51, c51;
	full_adder adder51 (.a(a[4] & b[7]), .b(a[5] & b[6]), .c(a[6] & b[5]), .sum(s51), .carry(c51));
	wire s52, c52;
	full_adder adder52 (.a(a[7] & b[4]), .b(~(a[3] & b[7] & b_is_signed)), .c(~(a[7] & a_is_signed & b[3])), .sum(s52), .carry(c52));
	wire s53, c53;
	full_adder adder53 (.a(c44), .b(c45), .c(s51), .sum(s53), .carry(c53));
	wire s54, c54;
	full_adder adder54 (.a(s52), .b(c46), .c(c47), .sum(s54), .carry(c54));
	wire s55, c55;
	full_adder adder55 (.a(s53), .b(c48), .c(s54), .sum(s55), .carry(c55));
	wire s56, c56;
	full_adder adder56 (.a(c49), .b(s55), .c(c50), .sum(s56), .carry(c56));
	wire s57, c57;
	full_adder adder57 (.a(a[5] & b[7]), .b(a[6] & b[6]), .c(a[7] & b[5]), .sum(s57), .carry(c57));
	wire s58, c58;
	full_adder adder58 (.a(~(a[4] & b[7] & b_is_signed)), .b(~(a[7] & a_is_signed & b[4])), .c(c51), .sum(s58), .carry(c58));
	wire s59, c59;
	full_adder adder59 (.a(c52), .b(s57), .c(s58), .sum(s59), .carry(c59));
	wire s60, c60;
	full_adder adder60 (.a(c53), .b(s59), .c(c54), .sum(s60), .carry(c60));
	wire s61, c61;
	full_adder adder61 (.a(s60), .b(c55), .c(c56), .sum(s61), .carry(c61));
	wire s62, c62;
	full_adder adder62 (.a(a[6] & b[7]), .b(a[7] & b[6]), .c(~(a[5] & b[7] & b_is_signed)), .sum(s62), .carry(c62));
	wire s63, c63;
	full_adder adder63 (.a(~(a[7] & a_is_signed & b[5])), .b(c57), .c(s62), .sum(s63), .carry(c63));
	wire s64, c64;
	full_adder adder64 (.a(c58), .b(c59), .c(s63), .sum(s64), .carry(c64));
	wire s65, c65;
	full_adder adder65 (.a(c60), .b(s64), .c(c61), .sum(s65), .carry(c65));
	wire s66, c66;
	full_adder adder66 (.a(a[7] & b[7]), .b(~(a[6] & b[7] & b_is_signed)), .c(~(a[7] & a_is_signed & b[6])), .sum(s66), .carry(c66));
	wire s67, c67;
	full_adder adder67 (.a(c62), .b(s66), .c(c63), .sum(s67), .carry(c67));
	wire s68, c68;
	full_adder adder68 (.a(s67), .b(c64), .c(c65), .sum(s68), .carry(c68));
	assign {mulh, mul} = {
		((((a[7] & b[7] & b_is_signed) ^ (a[7] & a_is_signed & b[7])) ^ (c66)) ^ (c67)) ^ (c68),
		s68,
		s65,
		s61,
		s56,
		s50,
		s43,
		s35,
		s27,
		s20,
		s14,
		s9,
		s5,
		s2,
		s0,
		a[0] & b[0]
	};
endmodule

module half_adder (
	input bit a,
	input bit b,
	output bit sum,
	output bit carry
);
	assign {carry, sum} = 2'(a) + 2'(b);
endmodule

module half_adder_plus_one (
	input bit a,
	input bit b,
	output bit sum,
	output bit carry
);
	assign {carry, sum} = 2'(a) + 2'(b) + 2'b01;
endmodule

module full_adder (
	input bit a,
	input bit b,
	input bit c,
	output bit sum,
	output bit carry
);
	assign {carry, sum} = 2'(a) + 2'(b) + 2'(c);
endmodule

`ifdef TESTING
module test_bww_multiplier;
	bit[7:0] a;
	bit a_is_signed;
	bit[7:0] b;
	bit b_is_signed;
	wire[7:0] mul;
	wire[7:0] mulh;
	bww_multiplier bww_multiplier_module (
		.a(a), .a_is_signed(a_is_signed),
		.b(b), .b_is_signed(b_is_signed),
		.mul(mul), .mulh(mulh)
	);

	initial begin
		a = -8'd1;
		a_is_signed = '0;
		b = -8'd1;
		b_is_signed = '0;
		#1
		assert(mul == 8'd1) else $fatal;
		assert(mulh == -8'd2) else $fatal;

		a = -8'd1;
		a_is_signed = '1;
		b = -8'd1;
		b_is_signed = '0;
		#1
		assert(mul == 8'd1) else $fatal;
		assert(mulh == -8'd1) else $fatal;

		a = -8'd1;
		a_is_signed = '0;
		b = -8'd1;
		b_is_signed = '1;
		#1
		assert(mul == 8'd1) else $fatal;
		assert(mulh == -8'd1) else $fatal;

		a = -8'd1;
		a_is_signed = '1;
		b = -8'd1;
		b_is_signed = '1;
		#1
		assert(mul == 8'd1) else $fatal;
		assert(mulh == 8'd0) else $fatal;
	end
endmodule
`endif
