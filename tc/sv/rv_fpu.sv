`define H_EXPONENT_LEN 5
`define H_SIGNIFICAND_LEN 10
`define H_LEN 16

`define S_EXPONENT_LEN 8
`define S_SIGNIFICAND_LEN 23
`define S_LEN 32

`define D_EXPONENT_LEN 11
`define D_SIGNIFICAND_LEN 52
`define D_LEN 64

`define I_EXPONENT_LEN 14
`define I_INTEGER_LEN 2
`define I_FRACTION_LEN 64
`define I_SIGNIFICAND_LEN (`I_INTEGER_LEN + `I_FRACTION_LEN)

typedef enum bit[1:0] {
	H = 2'b10,
	S = 2'b00,
	D = 2'b01,
	Q = 2'b11
} Fmt;

typedef enum {
	Finite,
	Infinity,
	NaN
} UnpackedTag;

typedef struct packed {
	UnpackedTag tag;
	bit sign;
	union packed {
		struct packed {
			bit[`I_EXPONENT_LEN - 1:0] exponent;
			bit[`I_SIGNIFICAND_LEN - 1:0] significand;
		} finite;

		struct packed {
			bit[`I_EXPONENT_LEN + `I_SIGNIFICAND_LEN - 1:0] _padding;
		} infinity;

		struct packed {
			bit quiet;
			bit[`I_EXPONENT_LEN + `I_SIGNIFICAND_LEN - 2:0] _padding;
		} nan;
	} value;
} Unpacked;

module rv_fpu (
	input bit[4:0] opcode,
	input bit[6:0] funct7,
	input bit[2:0] rm,
	input bit[4:0] funct5,

	input bit[63:0] rs1,
	input bit[63:0] rs2,
	input bit[63:0] rs3,

	output bit sigill,
	output bit[63:0] rd
);
	typedef enum bit[4:0] {
		OpCode_Madd = 5'b10000,
		OpCode_Msub = 5'b10001,
		OpCode_Nmsub = 5'b10010,
		OpCode_Nmadd = 5'b10011,
		OpCode_OpFp = 5'b10100
	} OpCode;

	Fmt fmt;
	Fmt fmt2;

	Fmt unpack_fmt;
	bit[63:0] unpack_arg1_value;
	Unpacked arg1;
	Unpack unpack_arg1 (
		unpack_fmt, unpack_arg1_value,
		arg1
	);
	bit[63:0] unpack_arg2_value;
	Unpacked arg2;
	Unpack unpack_arg2 (
		unpack_fmt, unpack_arg2_value,
		arg2
	);
	bit[63:0] unpack_arg3_value;
	Unpacked arg3;
	Unpack unpack_arg3 (
		unpack_fmt, unpack_arg3_value,
		arg3
	);

	Fmt pack_fmt;
	Unpacked result;
	bit[63:0] packed_result;
	Pack pack_rd (
		pack_fmt, result,
		packed_result
	);

	always_comb begin
		sigill = '0;

		fmt = Fmt'(funct7[0+:2]);
		fmt2 = Fmt'(funct5[0+:2]);

		unpack_fmt = fmt;
		unpack_arg1_value = rs1;
		unpack_arg2_value = rs2;
		unpack_arg3_value = rs3;

		pack_fmt = fmt;

		unique case (OpCode'(opcode))
			OpCode_OpFp: unique case (funct7[2+:5])
				5'b00000: unique case (fmt)
					// fadd.h
					H: begin
						rd = packed_result;
					end

					// fadd.s
					S: begin
						rd = packed_result;
					end

					// fadd.d
					D: begin
						rd = packed_result;
					end

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b00001: unique case (fmt)
					// fsub.h
					H: begin
						rd = packed_result;
					end

					// fsub.s
					S: begin
						rd = packed_result;
					end

					// fsub.d
					D: begin
						rd = packed_result;
					end

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b00010: unique case (fmt)
					// fmul.h
					H: begin
						rd = packed_result;
					end

					// fmul.s
					S: begin
						rd = packed_result;
					end

					// fmul.d
					D: begin
						rd = packed_result;
					end

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b00011: unique case (fmt)
					// fdiv.h
					H: begin
						rd = packed_result;
					end

					// fdiv.s
					S: begin
						rd = packed_result;
					end

					// fdiv.d
					D: begin
						rd = packed_result;
					end

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b00100: unique case (rm)
					3'b000: unique case (fmt)
						// fsgnj.h
						H: begin
						end

						// fsgnj.s
						S: begin
							result = arg1;
							result.sign = arg2.sign;
							rd = packed_result;
						end

						// fsgnj.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					3'b001: unique case (fmt)
						// fsgnjn.h
						H: begin
						end

						// fsgnjn.s
						S: begin
							result = arg1;
							result.sign = ~arg2.sign;
							rd = packed_result;
						end

						// fsgnjn.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					3'b010: unique case (fmt)
						// fsgnjx.h
						H: begin
						end

						// fsgnjx.s
						S: begin
							result = arg1;
							result.sign ^= arg2.sign;
							rd = packed_result;
						end

						// fsgnjx.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b00101: unique case (rm)
					3'b000: unique case (fmt)
						// fmin.h
						H: begin
						end

						// fmin.s
						S: begin
						end

						// fmin.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					3'b001: unique case (fmt)
						// fmax.h
						H: begin
						end

						// fmax.s
						S: begin
						end

						// fmax.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b01000: begin
					unpack_fmt = fmt2;

					unique case ({ funct5[2+:3], fmt, fmt2 })
						// fcvt.h.s
						{ 3'b000, H, S }: begin
							result = arg1;
							rd = packed_result;
						end

						// fcvt.h.d
						{ 3'b000, H, D }: begin
							result = arg1;
							rd = packed_result;
						end

						// fcvt.s.h
						{ 3'b000, S, H }: begin
							result = arg1;
							rd = packed_result;
						end

						// fcvt.s.d
						{ 3'b000, S, D }: begin
							result = arg1;
							rd = packed_result;
						end

						// fcvt.d.h
						{ 3'b000, D, H }: begin
							result = arg1;
							rd = packed_result;
						end

						// fcvt.d.s
						{ 3'b000, D, S }: begin
							result = arg1;
							rd = packed_result;
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase
				end

				5'b01011: unique case (funct5)
					5'b00000: unique case (fmt)
						// fsqrt.h
						H: begin
						end

						// fsqrt.s
						S: begin
						end

						// fsqrt.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b10100: unique case (rm)
					3'b000: unique case (fmt)
						// fle.h
						H: begin
						end

						// fle.s
						S: begin
						end

						// fle.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					3'b001: unique case (fmt)
						// flt.h
						H: begin
						end

						// flt.s
						S: begin
						end

						// flt.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					3'b010: unique case (fmt)
						// feq.h
						H: begin
						end

						// feq.s
						S: begin
						end

						// feq.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b11000: unique case (funct5)
					5'b00000: unique case (fmt)
						// fcvt.w.h
						H: begin
						end

						// fcvt.w.s
						S: begin
						end

						// fcvt.w.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					5'b00001: unique case (fmt)
						// fcvt.wu.h
						H: begin
						end

						// fcvt.wu.s
						S: begin
						end

						// fcvt.wu.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					5'b00010: unique case (fmt)
						// fcvt.l.h
						H: begin
						end

						// fcvt.l.s
						S: begin
						end

						// fcvt.l.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					5'b00011: unique case (fmt)
						// fcvt.lu.h
						H: begin
						end

						// fcvt.lu.s
						S: begin
						end

						// fcvt.lu.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b11010: unique case (funct5)
					5'b00000: unique case (fmt)
						// fcvt.h.w
						H: begin
						end

						// fcvt.s.w
						S: begin
						end

						// fcvt.d.w
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					5'b00001: unique case (fmt)
						// fcvt.h.wu
						H: begin
						end

						// fcvt.s.wu
						S: begin
						end

						// fcvt.d.wu
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					5'b00010: unique case (fmt)
						// fcvt.h.l
						H: begin
						end

						// fcvt.s.l
						S: begin
						end

						// fcvt.d.l
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					5'b00011: unique case (fmt)
						// fcvt.h.lu
						H: begin
						end

						// fcvt.s.lu
						S: begin
						end

						// fcvt.d.lu
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b11100: unique case ({ rm, funct5 })
					{ 3'b000, 5'b00000 }: unique case (fmt)
						// fmv.x.h
						H: begin
						end

						// fmv.x.s
						S: begin
						end

						// fmv.x.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					{ 3'b001, 5'b00000 }: unique case (fmt)
						// fclass.h
						H: begin
						end

						// fclass.s
						S: begin
						end

						// fclass.d
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				5'b11110: unique case ({ rm, funct5 })
					{ 3'b000, 5'b00000 }: unique case (fmt)
						// fmv.h.x
						H: begin
						end

						// fmv.w.x
						S: begin
						end

						// fmv.d.x
						D: begin
						end

						default: begin
							sigill = '1;
							rd = 'x;
							unpack_fmt = Fmt'('x);
							unpack_arg1_value = 'x;
							unpack_arg2_value = 'x;
							unpack_arg3_value = 'x;
							pack_fmt = Fmt'('x);
						end
					endcase

					default: begin
						sigill = '1;
						rd = 'x;
						unpack_fmt = Fmt'('x);
						unpack_arg1_value = 'x;
						unpack_arg2_value = 'x;
						unpack_arg3_value = 'x;
						pack_fmt = Fmt'('x);
					end
				endcase

				default: begin
					sigill = '1;
					rd = 'x;
					unpack_fmt = Fmt'('x);
					unpack_arg1_value = 'x;
					unpack_arg2_value = 'x;
					unpack_arg3_value = 'x;
					pack_fmt = Fmt'('x);
				end
			endcase

			OpCode_Madd: unique case (fmt)
				// fmadd.h
				H: begin
				end

				// fmadd.s
				S: begin
				end

				// fmadd.d
				D: begin
				end

				default: begin
					sigill = '1;
					rd = 'x;
					unpack_fmt = Fmt'('x);
					unpack_arg1_value = 'x;
					unpack_arg2_value = 'x;
					unpack_arg3_value = 'x;
					pack_fmt = Fmt'('x);
				end
			endcase

			OpCode_Msub: unique case (fmt)
				// fmsub.h
				H: begin
				end

				// fmsub.s
				S: begin
				end

				// fmsub.d
				D: begin
				end

				default: begin
					sigill = '1;
					rd = 'x;
					unpack_fmt = Fmt'('x);
					unpack_arg1_value = 'x;
					unpack_arg2_value = 'x;
					unpack_arg3_value = 'x;
					pack_fmt = Fmt'('x);
				end
			endcase

			OpCode_Nmsub: unique case (fmt)
				// fnmsub.h
				H: begin
				end

				// fnmsub.s
				S: begin
				end

				// fnmsub.d
				D: begin
				end

				default: begin
					sigill = '1;
					rd = 'x;
					unpack_fmt = Fmt'('x);
					unpack_arg1_value = 'x;
					unpack_arg2_value = 'x;
					unpack_arg3_value = 'x;
					pack_fmt = Fmt'('x);
				end
			endcase

			OpCode_Nmadd: unique case (fmt)
				// fnmadd.h
				H: begin
				end

				// fnmadd.s
				S: begin
				end

				// fnmadd.d
				D: begin
				end

				default: begin
					sigill = '1;
					rd = 'x;
					unpack_fmt = Fmt'('x);
					unpack_arg1_value = 'x;
					unpack_arg2_value = 'x;
					unpack_arg3_value = 'x;
					pack_fmt = Fmt'('x);
				end
			endcase

			default: begin
				sigill = '1;
				rd = 'x;
				unpack_fmt = Fmt'('x);
				unpack_arg1_value = 'x;
				unpack_arg2_value = 'x;
				unpack_arg3_value = 'x;
				pack_fmt = Fmt'('x);
			end
		endcase
	end
endmodule

module Unpack (
	input Fmt fmt,
	input bit[63:0] value,

	output Unpacked result
);
	always_comb begin
		result = 'x;
	end
endmodule

module Pack (
	input Fmt fmt,
	input Unpacked value,

	output bit[63:0] result
);
	always_comb begin
		result = 'x;
	end
endmodule
