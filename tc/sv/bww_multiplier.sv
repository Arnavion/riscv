module bww_multiplier (
	input bit[7:0] a,
	input bit a_is_signed,
	input bit[7:0] b,
	input bit b_is_signed,

	output bit[7:0] mul,
	output bit[7:0] mulh
);
	wire s0, c0;
	half_adder adder0(a[0] & b[1], a[1] & b[0], s0, c0);
	wire s1, c1;
	full_adder adder1 (a[0] & b[2], a[1] & b[1], a[2] & b[0], s1, c1);
	wire s2, c2;
	half_adder adder2(c0, s1, s2, c2);
	wire s3, c3;
	full_adder adder3 (a[0] & b[3], a[1] & b[2], a[2] & b[1], s3, c3);
	wire s4, c4;
	full_adder adder4 (a[3] & b[0], c1, s3, s4, c4);
	wire s5, c5;
	half_adder adder5(c2, s4, s5, c5);
	wire s6, c6;
	full_adder adder6 (a[0] & b[4], a[1] & b[3], a[2] & b[2], s6, c6);
	wire s7, c7;
	full_adder adder7 (a[3] & b[1], a[4] & b[0], c3, s7, c7);
	wire s8, c8;
	full_adder adder8 (s6, s7, c4, s8, c8);
	wire s9, c9;
	half_adder adder9(c5, s8, s9, c9);
	wire s10, c10;
	full_adder adder10 (a[0] & b[5], a[1] & b[4], a[2] & b[3], s10, c10);
	wire s11, c11;
	full_adder adder11 (a[3] & b[2], a[4] & b[1], a[5] & b[0], s11, c11);
	wire s12, c12;
	full_adder adder12 (c6, s10, s11, s12, c12);
	wire s13, c13;
	full_adder adder13 (c7, c8, s12, s13, c13);
	wire s14, c14;
	half_adder adder14(c9, s13, s14, c14);
	wire s15, c15;
	full_adder adder15 (a[0] & b[6], a[1] & b[5], a[2] & b[4], s15, c15);
	wire s16, c16;
	full_adder adder16 (a[3] & b[3], a[4] & b[2], a[5] & b[1], s16, c16);
	wire s17, c17;
	full_adder adder17 (a[6] & b[0], c10, c11, s17, c17);
	wire s18, c18;
	full_adder adder18 (s15, s16, c12, s18, c18);
	wire s19, c19;
	full_adder adder19 (s17, s18, c13, s19, c19);
	wire s20, c20;
	half_adder adder20(c14, s19, s20, c20);
	wire s21, c21;
	full_adder adder21 (a[0] & b[7], a[1] & b[6], a[2] & b[5], s21, c21);
	wire s22, c22;
	full_adder adder22 (a[3] & b[4], a[4] & b[3], a[5] & b[2], s22, c22);
	wire s23, c23;
	full_adder adder23 (a[6] & b[1], a[7] & b[0], c15, s23, c23);
	wire s24, c24;
	full_adder adder24 (c16, s21, s22, s24, c24);
	wire s25, c25;
	full_adder adder25 (s23, c17, s24, s25, c25);
	wire s26, c26;
	full_adder adder26 (c18, s25, c19, s26, c26);
	wire s27, c27;
	half_adder adder27(c20, s26, s27, c27);
	wire s28, c28;
	full_adder adder28 (a[1] & b[7], a[2] & b[6], a[3] & b[5], s28, c28);
	wire s29, c29;
	full_adder adder29 (a[4] & b[4], a[5] & b[3], a[6] & b[2], s29, c29);
	wire s30, c30;
	full_adder adder30 (a[7] & b[1], ~(a[0] & b[7] & b_is_signed), ~(a[7] & a_is_signed & b[0]), s30, c30);
	wire s31, c31;
	full_adder adder31 (c21, c22, s28, s31, c31);
	wire s32, c32;
	full_adder adder32 (s29, c23, s30, s32, c32);
	wire s33, c33;
	full_adder adder33 (c24, s31, s32, s33, c33);
	wire s34, c34;
	full_adder adder34 (c25, s33, c26, s34, c34);
	wire s35, c35;
	half_adder adder35(c27, s34, s35, c35);
	wire s36, c36;
	full_adder adder36 (a[2] & b[7], a[3] & b[6], a[4] & b[5], s36, c36);
	wire s37, c37;
	full_adder adder37 (a[5] & b[4], a[6] & b[3], a[7] & b[2], s37, c37);
	wire s38, c38;
	full_adder adder38 (~(a[1] & b[7] & b_is_signed), ~(a[7] & a_is_signed & b[1]), c28, s38, c38);
	wire s39, c39;
	full_adder adder39 (c29, c30, s36, s39, c39);
	wire s40, c40;
	full_adder adder40 (s37, s38, c31, s40, c40);
	wire s41, c41;
	full_adder adder41 (c32, s39, s40, s41, c41);
	wire s42, c42;
	full_adder adder42 (c33, s41, c34, s42, c42);
	wire s43, c43;
	half_adder_plus_one adder43 (c35, s42, s43, c43);
	wire s44, c44;
	full_adder adder44 (a[3] & b[7], a[4] & b[6], a[5] & b[5], s44, c44);
	wire s45, c45;
	full_adder adder45 (a[6] & b[4], a[7] & b[3], ~(a[2] & b[7] & b_is_signed), s45, c45);
	wire s46, c46;
	full_adder adder46 (~(a[7] & a_is_signed & b[2]), c36, c37, s46, c46);
	wire s47, c47;
	full_adder adder47 (s44, s45, c38, s47, c47);
	wire s48, c48;
	full_adder adder48 (c39, s46, c40, s48, c48);
	wire s49, c49;
	full_adder adder49 (s47, c41, s48, s49, c49);
	wire s50, c50;
	full_adder adder50 (s49, c42, c43, s50, c50);
	wire s51, c51;
	full_adder adder51 (a[4] & b[7], a[5] & b[6], a[6] & b[5], s51, c51);
	wire s52, c52;
	full_adder adder52 (a[7] & b[4], ~(a[3] & b[7] & b_is_signed), ~(a[7] & a_is_signed & b[3]), s52, c52);
	wire s53, c53;
	full_adder adder53 (c44, c45, s51, s53, c53);
	wire s54, c54;
	full_adder adder54 (s52, c46, c47, s54, c54);
	wire s55, c55;
	full_adder adder55 (s53, c48, s54, s55, c55);
	wire s56, c56;
	full_adder adder56 (c49, s55, c50, s56, c56);
	wire s57, c57;
	full_adder adder57 (a[5] & b[7], a[6] & b[6], a[7] & b[5], s57, c57);
	wire s58, c58;
	full_adder adder58 (~(a[4] & b[7] & b_is_signed), ~(a[7] & a_is_signed & b[4]), c51, s58, c58);
	wire s59, c59;
	full_adder adder59 (c52, s57, s58, s59, c59);
	wire s60, c60;
	full_adder adder60 (c53, s59, c54, s60, c60);
	wire s61, c61;
	full_adder adder61 (s60, c55, c56, s61, c61);
	wire s62, c62;
	full_adder adder62 (a[6] & b[7], a[7] & b[6], ~(a[5] & b[7] & b_is_signed), s62, c62);
	wire s63, c63;
	full_adder adder63 (~(a[7] & a_is_signed & b[5]), c57, s62, s63, c63);
	wire s64, c64;
	full_adder adder64 (c58, c59, s63, s64, c64);
	wire s65, c65;
	full_adder adder65 (c60, s64, c61, s65, c65);
	wire s66, c66;
	full_adder adder66 (a[7] & b[7], ~(a[6] & b[7] & b_is_signed), ~(a[7] & a_is_signed & b[6]), s66, c66);
	wire s67, c67;
	full_adder adder67 (c62, s66, c63, s67, c67);
	wire s68, c68;
	full_adder adder68 (s67, c64, c65, s68, c68);
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
		a, a_is_signed,
		b, b_is_signed,
		mul, mulh
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
