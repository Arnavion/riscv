import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import Common::*;

`define H_EXPONENT_LEN 5
`define H_SIGNIFICAND_LEN 10
`define H_LEN 16

`define S_EXPONENT_LEN 8
`define S_SIGNIFICAND_LEN 23
`define S_LEN 32

`define D_EXPONENT_LEN 11
`define D_SIGNIFICAND_LEN 52
`define D_LEN 64

`define I_EXPONENT_LEN 13
`define I_INTEGER_LEN 2
`define I_FRACTION_LEN 58
`define I_SIGNIFICAND_LEN TAdd#(`I_INTEGER_LEN, `I_FRACTION_LEN)

typedef Bit#(TAdd#(1, TAdd#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN))) Packed;

typedef enum {
	H = 2'b10,
	S = 2'b00,
	D = 2'b01
	// Q = 2'b11
} Width deriving(Bits, FShow);

typedef enum {
	Rne = 3'b000, // round to nearest, ties to even
	Rtz = 3'b001, // round towards zero
	Rdn = 3'b010, // round down (towards -Infinity)
	Rup = 3'b011, // round up (towards +Infinity)
	Rmm = 3'b100  // round to nearest, ties to max magnitude
} RoundingMode deriving(Bits, Eq, FShow);

typedef struct {
	Bool nv; // invalid operation
	Bool dz; // divide by zero
	Bool of; // overflow
	Bool uf; // underflow
	Bool nx; // inexact
} Flags deriving(Eq, FShow);

Flags flagsNone = Flags { nv: False, dz: False, of: False, uf: False, nx: False };
Flags flagsNv = Flags { nv: True, dz: False, of: False, uf: False, nx: False };
Flags flagsDz = Flags { nv: False, dz: True, of: False, uf: False, nx: False };
// Overflow also always signals Inexact
Flags flagsOf = Flags { nv: False, dz: False, of: True, uf: False, nx: True };
// Underflow also always signals Inexact
Flags flagsUf = Flags { nv: False, dz: False, of: False, uf: True, nx: True };
Flags flagsNx = Flags { nv: False, dz: False, of: False, uf: False, nx: True };

instance Bits#(Flags, 5);
	function Bit#(5) pack(Flags flags);
		let nv = pack(flags.nv);
		let dz = pack(flags.dz);
		let of = pack(flags.of);
		let uf = pack(flags.uf);
		let nx = pack(flags.nx);
		return { nv, dz, of, uf, nx };
	endfunction

	function Flags unpack(Bit#(5) bits);
		let nv = unpack(bits[4]);
		let dz = unpack(bits[3]);
		let of = unpack(bits[2]);
		let uf = unpack(bits[1]);
		let nx = unpack(bits[0]);
		return Flags { nv: nv, dz: dz, of: of, uf: uf, nx: nx };
	endfunction
endinstance

typedef Server#(RvFpuRequest, RvFpuResponse) RvFpu;

typedef union tagged {
	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
	} Add;

	struct {
		Width width;
		Packed arg;
	} Classify;

	struct {
		RoundingMode rm;
		Width in;
		Width out;
		Packed arg;
	} Convert;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
		Packed arg3;
	} FusedMultiplyAdd;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
		Packed arg3;
	} FusedNegativeMultiplyAdd;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
		Packed arg3;
	} FusedNegativeMultiplySubtract;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
		Packed arg3;
	} FusedMultiplySubtract;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
	} Multiply;

	struct {
		SignInjectOp op;
		Width width;
		Packed arg1;
		Packed arg2;
	} SignInject;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg;
	} Sqrt;

	struct {
		RoundingMode rm;
		Width width;
		Packed arg1;
		Packed arg2;
	} Subtract;
} RvFpuRequest deriving(Bits, FShow);

typedef struct {
	Packed result;
	Flags flags;
} RvFpuResponse deriving(Bits, Eq, FShow);

typedef enum {
	Sgnj,
	Sgnjn,
	Sgnjx
} SignInjectOp deriving(Bits, FShow);

(* synthesize *)
module mkRvFpu(RvFpu);
	Unpack unpack_arg1 <- mkUnpack;
	Unpack unpack_arg2 <- mkUnpack;
	Unpack unpack_arg3 <- mkUnpack;
	Add adder <- mkAdd;
	Classify classifier <- mkClassify;
	Multiply multiplier <- mkMultiply;
	SignInject sign_injector <- mkSignInject;
	Sqrt sqrt <- mkSqrt;
	Pack pack_result <- mkPack;

	FIFO#(RvFpuRequest) args_ <- mkBypassFIFO;
	GetS#(RvFpuRequest) args = fifoToGetS(args_);
	FIFO#(RvFpuResponse) result_ <- mkBypassFIFO;
	Put#(RvFpuResponse) result = toPut(result_);

	rule add_1(args.first matches tagged Add { width: .width, arg1: .arg1, arg2: .arg2 });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg1 });
		unpack_arg2.request.put(UnpackRequest { width: width, value: arg2 });
	endrule

	rule add_2(args.first matches tagged Add { rm: .rm });
		match UnpackResponse { value: .arg1 } = unpack_arg1.response.first;
		match UnpackResponse { value: .arg2 } = unpack_arg2.response.first;
		adder.request.put(AddRequest { arg1: Unpacked { value: arg1, inexact: False }, arg2: arg2, rm: rm });
	endrule

	rule add_3(args.first matches tagged Add { rm: .rm, width: .width });
		match AddResponse { result: .result } = adder.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: result, was_divide_by_zero: False });
	endrule

	rule add_end(args.first matches tagged Add ._);
		match PackResponse { result: .packed_, flags: .flags } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_, flags: flags });
	endrule

	rule classify_1(args.first matches tagged Classify { width: .width, arg: .arg });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg });
	endrule

	rule classify_2(args.first matches tagged Classify ._);
		match UnpackResponse { value: .value } = unpack_arg1.response.first;
		classifier.request.put(ClassifyRequest { arg: value });
	endrule

	rule classify_end(args.first matches tagged Classify ._);
		match ClassifyResponse { result: .value } = classifier.response.first;
		result.put(RvFpuResponse { result: extend(value), flags: flagsNone });
	endrule

	rule convert_1(args.first matches tagged Convert { in: .width, arg: .arg });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg });
	endrule

	rule convert_2(args.first matches tagged Convert { rm: .rm, out: .width });
		match UnpackResponse { value: .value } = unpack_arg1.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: Unpacked { value: value, inexact: False }, was_divide_by_zero: False });
	endrule

	rule convert_end(args.first matches tagged Convert ._);
		match PackResponse { result: .packed_, flags: .flags } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_, flags: flags });
	endrule

	rule fused_multiply_add_1(args.first matches tagged FusedMultiplyAdd { width: .width, arg1: .arg1, arg2: .arg2, arg3: .arg3 });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg1 });
		unpack_arg2.request.put(UnpackRequest { width: width, value: arg2 });
		unpack_arg3.request.put(UnpackRequest { width: width, value: arg3 });
	endrule

	rule fused_multiply_add_2(args.first matches tagged FusedMultiplyAdd ._);
		match UnpackResponse { value: .arg1 } = unpack_arg1.response.first;
		match UnpackResponse { value: .arg2 } = unpack_arg2.response.first;
		multiplier.request.put(MultiplyRequest { arg1: arg1, arg2: arg2 });
	endrule

	rule fused_multiply_add_3(args.first matches tagged FusedMultiplyAdd { rm: .rm });
		match MultiplyResponse { result: .product } = multiplier.response.first;
		match UnpackResponse { value: .arg3 } = unpack_arg3.response.first;
		adder.request.put(AddRequest { arg1: product, arg2: arg3, rm: rm });
	endrule

	rule fused_multiply_add_4(args.first matches tagged FusedMultiplyAdd { rm: .rm, width: .width });
		match AddResponse { result: .result } = adder.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: result, was_divide_by_zero: False });
	endrule

	rule fused_multiply_add_end(args.first matches tagged FusedMultiplyAdd ._);
		match PackResponse { result: .packed_, flags: .flags } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_, flags: flags });
	endrule

	rule multiply_1(args.first matches tagged Multiply { width: .width, arg1: .arg1, arg2: .arg2 });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg1 });
		unpack_arg2.request.put(UnpackRequest { width: width, value: arg2 });
	endrule

	rule multiply_2(args.first matches tagged Multiply ._);
		match UnpackResponse { value: .arg1 } = unpack_arg1.response.first;
		match UnpackResponse { value: .arg2 } = unpack_arg2.response.first;
		multiplier.request.put(MultiplyRequest { arg1: arg1, arg2: arg2 });
	endrule

	rule multiply_3(args.first matches tagged Multiply { rm: .rm, width: .width });
		match MultiplyResponse { result: .result } = multiplier.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: result, was_divide_by_zero: False });
	endrule

	rule multiply_end(args.first matches tagged Multiply ._);
		match PackResponse { result: .packed_, flags: .flags } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_, flags: flags });
	endrule

	rule sign_inject_1(args.first matches tagged SignInject { op: .op, width: .width, arg1: .arg1, arg2: .arg2 });
		sign_injector.request.put(SignInjectRequest { op: op, width: width, arg1: arg1, arg2: arg2 });
	endrule

	rule sign_inject_end(args.first matches tagged SignInject ._);
		match SignInjectResponse { result: .sign_inject_result } = sign_injector.response.first;
		result.put(RvFpuResponse { result: sign_inject_result, flags: flagsNone });
	endrule

	rule sqrt_1(args.first matches tagged Sqrt { width: .width, arg: .arg });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg });
	endrule

	rule sqrt_2(args.first matches tagged Sqrt ._);
		match UnpackResponse { value: .arg } = unpack_arg1.response.first;
		sqrt.request.put(SqrtRequest { arg: arg });
	endrule

	rule sqrt_3(args.first matches tagged Sqrt { rm: .rm, width: .width });
		match SqrtResponse { result: .result } = sqrt.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: result, was_divide_by_zero: False });
	endrule

	rule sqrt_end(args.first matches tagged Sqrt ._);
		match PackResponse { result: .packed_, flags: .flags } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_, flags: flags });
	endrule

	rule sub_1(args.first matches tagged Subtract { width: .width, arg1: .arg1, arg2: .arg2 });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg1 });
		unpack_arg2.request.put(UnpackRequest { width: width, value: arg2 });
	endrule

	rule sub_2(args.first matches tagged Subtract { rm: .rm });
		match UnpackResponse { value: .arg1 } = unpack_arg1.response.first;
		match UnpackResponse { value: .arg2 } = unpack_arg2.response.first;
		arg2 = case (arg2) matches
			tagged Finite { sign: .sign, exponent: .exponent, significand: .significand }: return tagged Finite { sign: !sign, exponent: exponent, significand: significand };
			tagged Infinity { sign: .sign }: return tagged Infinity { sign: !sign };
			tagged NaN { sign: .sign, quiet: .quiet }: return tagged NaN { sign: !sign, quiet: quiet };
		endcase;
		adder.request.put(AddRequest { arg1: Unpacked { value: arg1, inexact: False }, arg2: arg2, rm: rm });
	endrule

	rule sub_3(args.first matches tagged Subtract { rm: .rm, width: .width });
		match AddResponse { result: .result } = adder.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: result, was_divide_by_zero: False });
	endrule

	rule sub_end(args.first matches tagged Subtract ._);
		match PackResponse { result: .packed_, flags: .flags } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_, flags: flags });
	endrule

	interface request = toPut(args_);

	interface GetS response;
		method RvFpuResponse first = result_.first;

		method Action deq;
			args_.deq;

			case (args.first) matches
				tagged Add ._: begin
					unpack_arg1.response.deq;
					unpack_arg2.response.deq;
					adder.response.deq;
					pack_result.response.deq;
				end

				tagged Classify ._: begin
					unpack_arg1.response.deq;
					classifier.response.deq;
				end

				tagged Convert ._: begin
					unpack_arg1.response.deq;
					pack_result.response.deq;
				end

				tagged FusedMultiplyAdd ._: begin
					unpack_arg1.response.deq;
					unpack_arg2.response.deq;
					unpack_arg3.response.deq;
					multiplier.response.deq;
					adder.response.deq;
					pack_result.response.deq;
				end

				tagged Multiply ._: begin
					unpack_arg1.response.deq;
					unpack_arg2.response.deq;
					multiplier.response.deq;
					pack_result.response.deq;
				end

				tagged SignInject ._: begin
					unpack_arg1.response.deq;
					unpack_arg2.response.deq;
					sign_injector.response.deq;
					pack_result.response.deq;
				end

				tagged Sqrt ._: begin
					unpack_arg1.response.deq;
					sqrt.response.deq;
					pack_result.response.deq;
				end

				tagged Subtract ._: begin
					unpack_arg1.response.deq;
					unpack_arg2.response.deq;
					adder.response.deq;
					pack_result.response.deq;
				end
			endcase

			result_.deq;
		endmethod
	endinterface
endmodule

typedef union tagged {
	struct {
		Bool sign;
		Int#(`I_EXPONENT_LEN) exponent;
		UInt#(`I_SIGNIFICAND_LEN) significand;
	} Finite;

	struct {
		Bool sign;
	} Infinity;

	struct {
		Bool sign;
		Bool quiet;
	} NaN;
} UnpackedValue;

typedef struct {
	UnpackedValue value;
	Bool inexact;
} Unpacked deriving(Bits);

instance Bits#(UnpackedValue, TAdd#(1, TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN)));
	function Bit#(TAdd#(1, TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN))) pack(UnpackedValue value);
		Bool sign_ = ?;
		Int#(`I_EXPONENT_LEN) exponent_ = ?;
		UInt#(`I_SIGNIFICAND_LEN) significand_ = ?;

		case (value) matches
			tagged Finite { sign: .sign, exponent: .exponent, significand: .significand }: begin
				sign_ = sign;
				exponent_ = exponent;
				significand_ = significand;
			end

			tagged Infinity { sign: .sign }: begin
				sign_ = sign;
				exponent_ = unpack({ 1'b0, '1 });
				significand_ = unpack({ 2'b00, ? });
			end

			tagged NaN { sign: .sign, quiet: .quiet }: begin
				sign_ = sign;
				exponent_ = unpack({ 1'b0, '1 });
				significand_ = unpack({ pack(quiet), pack(!quiet), ? });
			end
		endcase

		return { pack(sign_), pack(exponent_), pack(significand_) };
	endfunction

	function UnpackedValue unpack(Bit#(TAdd#(1, TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN))) bits);
		Tuple2#(Bit#(1), Bit#(TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN))) parts1 = split(bits);
		match { .sign, .rest } = parts1;

		Tuple2#(Bit#(`I_EXPONENT_LEN), Bit#(`I_SIGNIFICAND_LEN)) parts2 = split(rest);
		match { .exponent, .significand } = parts2;

		if (exponent == { 1'b0, '1 }) begin
			Tuple2#(Bit#(2), Bit#(TSub#(`I_SIGNIFICAND_LEN, 2))) parts3 = split(significand);
			if (tpl_1(parts3) == '0)
				return tagged Infinity { sign: unpack(sign) };
			else
				return tagged NaN { sign: unpack(sign), quiet: unpack(msb(significand)) };
		end else
			return tagged Finite {
				sign: unpack(sign),
				exponent: unpack(exponent),
				significand: unpack(significand)
			};
	endfunction
endinstance

UnpackedValue canonical_nan = tagged NaN { sign: False, quiet: True };

typedef Server#(UnpackRequest, UnpackResponse) Unpack;

typedef struct {
	Width width;
	Packed value;
} UnpackRequest deriving(Bits);

typedef struct {
	UnpackedValue value;
} UnpackResponse deriving(Bits);

(* synthesize *)
module mkUnpack(Unpack);
	FIFO#(UnpackRequest) args_ <- mkBypassFIFO;
	GetS#(UnpackRequest) args = fifoToGetS(args_);
	FIFO#(UnpackResponse) result_ <- mkBypassFIFO;
	Put#(UnpackResponse) result = toPut(result_);

	rule run(args.first matches UnpackRequest { width: .width, value: .value });
		let unpacked = unpack_(width, value);
		result.put(UnpackResponse { value: unpacked });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

typedef struct {
	Bit#(TSub#(`D_LEN, TAdd#(1, TAdd#(exponent_len, significand_len)))) upper;
	Bit#(1) sign;
	Bit#(exponent_len) exponent;
	Bit#(significand_len) significand;
} UnpackedValueInner#(numeric type exponent_len, numeric type significand_len);

function UnpackedValue unpack_(Width width, Packed value);
	case (width) matches
		H: begin
			UnpackedValueInner#(`H_EXPONENT_LEN, `H_SIGNIFICAND_LEN) unpacked = unpack_inner1(value);
			return unpack_inner2(unpacked);
		end
		S: begin
			UnpackedValueInner#(`S_EXPONENT_LEN, `S_SIGNIFICAND_LEN) unpacked = unpack_inner1(value);
			return unpack_inner2(unpacked);
		end
		D: begin
			UnpackedValueInner#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN) unpacked = unpack_inner1(value);
			return unpack_inner2(unpacked);
		end
	endcase
endfunction

function UnpackedValueInner#(exponent_len, significand_len) unpack_inner1(Packed value)
provisos (
	Add#(a__, 1, significand_len)
);
	let exponent_len = valueOf(exponent_len);
	let significand_len = valueOf(significand_len);

	let lower_len = 1 + exponent_len + significand_len;
	let upper_len = valueOf(SizeOf#(Packed)) - lower_len;

	Tuple2#(Bit#(TSub#(SizeOf#(Packed), lower_len)), Bit#(lower_len)) parts0 = split(value);
	match { .upper_, .lower } = parts0;
	Bit#(TSub#(SizeOf#(Packed), TAdd#(1, TAdd#(exponent_len, significand_len)))) upper = upper_;

	Tuple2#(Bit#(1), Bit#(TAdd#(exponent_len, significand_len))) parts1 = split(lower);
	match { .sign, .rest } = parts1;

	Tuple2#(Bit#(exponent_len), Bit#(significand_len)) parts2 = split(rest);
	match { .exponent, .significand } = parts2;

	if (upper_len == 0 || upper == '1)
		return UnpackedValueInner {
			upper: upper,
			sign: sign,
			exponent: exponent,
			significand: significand
		};
	else
		// Not boxed correctly. Return canonical NaN.
		return UnpackedValueInner {
			upper: '1,
			sign: '0,
			exponent: '1,
			significand: { 1'b1, '0 }
		};
endfunction

function UnpackedValue unpack_inner2(UnpackedValueInner#(exponent_len, significand_len) value)
provisos (
	Add#(exponent_len, a__, `I_EXPONENT_LEN),
	Add#(significand_len, b__, `I_FRACTION_LEN)
);
	let exponent_len = valueOf(exponent_len);
	let significand_len = valueOf(significand_len);
	let lower_len = 1 + exponent_len + significand_len;
	let upper_len = valueOf(SizeOf#(Packed)) - lower_len;

	match UnpackedValueInner { sign: .sign, exponent: .exponent, significand: .significand } = value;

	let bias = (1 << (exponent_len - 1)) - 1;

	case ({ & exponent, | significand }) matches
		2'b11: return tagged NaN { sign: unpack(sign), quiet: unpack(msb(significand)) };

		2'b10: return tagged Infinity { sign: unpack(sign) };

		// Finite
		default: begin
			let exponent_ = (unpack(| exponent) ? unpack(extend(exponent)) : 1) - bias;

			// 1.significand_len
			Bit#(TAdd#(1, significand_len)) significand_a = { | exponent, significand };
			// 1.I_FRACTION_LEN
			Bit#(TAdd#(1, `I_FRACTION_LEN)) significand_b = { significand_a, '0 };
			// I_INTEGER_LEN.I_FRACTION_LEN
			Bit#(`I_SIGNIFICAND_LEN) significand_c = extend(significand_b);

			match { .exponent, .significand_d, ._ } = normalize_significand(exponent_, unpack(significand_c));

			return tagged Finite {
				sign: unpack(sign),
				exponent: exponent,
				significand: significand_d
			};
		end
	endcase
endfunction

typedef Server#(PackRequest, PackResponse) Pack;

typedef struct {
	Width width;
	RoundingMode rm;
	Unpacked value;
	Bool was_divide_by_zero;
} PackRequest deriving(Bits);

typedef struct {
	Packed result;
	Flags flags;
} PackResponse deriving(Bits);

(* synthesize *)
module mkPack(Pack);
	FIFO#(PackRequest) args_ <- mkBypassFIFO;
	GetS#(PackRequest) args = fifoToGetS(args_);
	FIFO#(PackResponse) result_ <- mkBypassFIFO;
	Put#(PackResponse) result = toPut(result_);

	rule run(args.first matches PackRequest { width: .width, rm: .rm, value: .value, was_divide_by_zero: .was_divide_by_zero });
		case (width) matches
			H: begin
				Tuple2#(UnpackedValueInner#(`H_EXPONENT_LEN, `H_SIGNIFICAND_LEN), Flags) rounded = round(rm, value, was_divide_by_zero);
				match { .rounded_value, .flags } = rounded;
				result.put(PackResponse {
					result: {
						rounded_value.upper,
						pack(rounded_value.sign),
						rounded_value.exponent,
						rounded_value.significand
					},
					flags: flags
				});
			end

			S: begin
				Tuple2#(UnpackedValueInner#(`S_EXPONENT_LEN, `S_SIGNIFICAND_LEN), Flags) rounded = round(rm, value, was_divide_by_zero);
				match { .rounded_value, .flags } = rounded;
				result.put(PackResponse {
					result: {
						rounded_value.upper,
						pack(rounded_value.sign),
						rounded_value.exponent,
						rounded_value.significand
					},
					flags: flags
				});
			end

			D: begin
				Tuple2#(UnpackedValueInner#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN), Flags) rounded = round(rm, value, was_divide_by_zero);
				match { .rounded_value, .flags } = rounded;
				result.put(PackResponse {
					result: {
						rounded_value.upper,
						pack(rounded_value.sign),
						rounded_value.exponent,
						rounded_value.significand
					},
					flags: flags
				});
			end
		endcase
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Tuple2#(UnpackedValueInner#(exponent_len, significand_len), Flags) round(
	RoundingMode rm,
	Unpacked value,
	Bool was_divide_by_zero
)
provisos (
	Add#(exponent_len, a__, `I_EXPONENT_LEN),
	Add#(1, b__, exponent_len),
	Add#(1, TAdd#(1, c__), significand_len),
	Add#(significand_len, d__, `I_FRACTION_LEN),
	Add#(significand_len, e__, TAdd#(`I_INTEGER_LEN, `I_FRACTION_LEN))
);
	let exponent_len = valueOf(exponent_len);
	let significand_len = valueOf(significand_len);

	let bias = (1 << (exponent_len - 1)) - 1;
	Int#(`I_EXPONENT_LEN) normal_exponent_max = bias;
	Int#(`I_EXPONENT_LEN) normal_exponent_min = -bias + 1;

	case (value.value) matches
		tagged Finite { sign: .sign, exponent: .exponent_, significand: .significand_ }: begin
			Int#(`I_EXPONENT_LEN) exponent = exponent_;
			UInt#(`I_SIGNIFICAND_LEN) significand = significand_;

			let inexact = value.inexact;
			let underflow = False;

			begin
				match { .rounded_exponent, .rounded_significand } = round_significand(sign, Bit#(significand_len)'(?), rm, exponent, significand);
				if (rounded_exponent < normal_exponent_min) begin
					underflow = True;
				end
			end

			begin
				match { .normalized_exponent, .normalized_significand, .inexact_ } = normalize_finite(exponent_len, exponent, significand);
				inexact = inexact || inexact_;
				match { .rounded_exponent, .rounded_significand_ } = round_significand(sign, Bit#(significand_len)'(?), rm, normalized_exponent, normalized_significand);
				exponent = rounded_exponent;
				significand = rounded_significand_;
				inexact = inexact || (rounded_significand_ != normalized_significand);

				UInt#(TSub#(`I_SIGNIFICAND_LEN, TSub#(`I_FRACTION_LEN, significand_len))) rounded_significand = unpack(truncateLSB(pack(significand)));

				if (exponent > normal_exponent_max) begin
					let infinity = tuple2(
						UnpackedValueInner {
							upper: '1,
							sign: pack(sign),
							exponent: '1,
							significand: '0
						},
						was_divide_by_zero ? flagsDz : flagsOf
					);
					let finite_max = tuple2(
						UnpackedValueInner {
							upper: '1,
							sign: pack(sign),
							exponent: { '1, 1'b0 },
							significand: '1
						},
						flagsOf
					);
					case (rm) matches
						Rne: return infinity;
						Rtz: return finite_max;
						Rdn: return sign ? infinity : finite_max;
						Rup: return sign ? finite_max : infinity;
						Rmm: return infinity;
					endcase
				end else begin
					let significand_lt1 = unpack(~| (pack(significand) >> `I_FRACTION_LEN));
					return tuple2(
						UnpackedValueInner {
							upper: '1,
							sign: pack(sign),
							exponent: significand_lt1 ? '0 : truncate(pack(exponent + bias)),
							significand: truncateLSB(pack(significand << `I_INTEGER_LEN))
						},
						inexact ?
							(
								underflow ?
									flagsUf :
									flagsNx
							) :
							flagsNone
					);
				end
			end
		end

		tagged Infinity { sign: .sign }: return tuple2(
			UnpackedValueInner {
				upper: '1,
				sign: pack(sign),
				exponent: '1,
				significand: '0
			},
			was_divide_by_zero ? flagsDz : flagsNone
		);

		// Return canonical NaN, but set nv if the input was a signaling NaN.
		tagged NaN { quiet: .quiet }: return tuple2(
			UnpackedValueInner {
				upper: '1,
				sign: '0,
				exponent: '1,
				significand: { 1'b1, '0 }
			},
			quiet ? flagsNone : flagsNv
		);
	endcase
endfunction

function Tuple3#(Int#(`I_EXPONENT_LEN), UInt#(`I_SIGNIFICAND_LEN), Bool) normalize_significand(
	Int#(`I_EXPONENT_LEN) exponent,
	UInt#(significand_len) significand
)
provisos (
	Add#(`I_SIGNIFICAND_LEN, a__, significand_len),
	Add#(1, b__, significand_len),
	Add#(TLog#(TAdd#(1, significand_len)), c__, 13)
);
	let significand_len = valueOf(significand_len);

	let significand_ne0 = unpack(| pack(significand));
	if (significand_ne0) begin
		let leading_zeros = countZerosMSB(pack(significand));
		Int#(`I_EXPONENT_LEN) shift_by = fromInteger(significand_len - `I_FRACTION_LEN - 1) - unpack(pack(extend(leading_zeros)));

		// 0.1e1 -> 1e0 until 1eX
		// 2e19 -> 1e20 until 1eX
		match { .significand_, .inexact } = shift_accumulate(significand, shift_by);

		return tuple3(exponent + shift_by, truncate(significand_), inexact);
	end else
		// Zero
		return tuple3(0, truncate(significand), False);
endfunction

function Tuple3#(Int#(`I_EXPONENT_LEN), UInt#(`I_SIGNIFICAND_LEN), Bool) normalize_finite(
	Integer exponent_len,
	Int#(`I_EXPONENT_LEN) exponent,
	UInt#(`I_SIGNIFICAND_LEN) significand
);
	// exponent_len == 5 =>
	//     bias                =  15
	//     subnormal_exponent  = -15
	//     normal_exponent_min = -14
	//     normal_exponent_max =  15
	//     infinite_exponent   =  16
	let bias = (1 << (exponent_len - 1)) - 1;
	Int#(`I_EXPONENT_LEN) normal_exponent_min = -bias + 1;
	Int#(`I_EXPONENT_LEN) normal_exponent_max = bias;

	let significand_ne0 = unpack(| pack(significand));
	if (significand_ne0) begin
		let leading_zeros = countZerosMSB(pack(significand));

		Int#(`I_EXPONENT_LEN) shift_by = (`I_INTEGER_LEN - 1) - unpack(pack(extend(leading_zeros)));
		Int#(`I_EXPONENT_LEN) shift_by_min_for_exponent = normal_exponent_min - exponent;
		shift_by = max(shift_by, shift_by_min_for_exponent);

		// 0.1e1 -> 1e0 until 1eX or Xe-14
		// 2e19 -> 1e20 until 1eX
		match { .significand_, .inexact } = shift_accumulate(significand, shift_by);
		significand = significand_;
		exponent = exponent + shift_by;

		return tuple3(exponent, significand, inexact);
	end else
		// Zero
		return tuple3(0, significand, False);
endfunction

function Tuple2#(Int#(`I_EXPONENT_LEN), UInt#(`I_SIGNIFICAND_LEN)) round_significand(
	Bool sign,
	Bit#(significand_len) _,
	RoundingMode rm,
	Int#(`I_EXPONENT_LEN) exponent,
	UInt#(`I_SIGNIFICAND_LEN) significand
);
	let significand_ne0 = unpack(| pack(significand));
	if (significand_ne0) begin
		Tuple2#(
			Bit#(TAdd#(`I_INTEGER_LEN, significand_len)),
			Bit#(TSub#(`I_FRACTION_LEN, significand_len))
		) significand_parts = split(pack(significand));
		match { .rounded_significand_, .excess_significand } = significand_parts;
		UInt#(TAdd#(`I_INTEGER_LEN, significand_len)) rounded_significand = unpack(rounded_significand_);

		Tuple2#(Bit#(1), Bit#(TSub#(TSub#(`I_FRACTION_LEN, significand_len), 1))) excess_significand_parts = split(excess_significand);
		let excess_significand_msb = tpl_1(excess_significand_parts);
		let excess_significand_rest = | tpl_2(excess_significand_parts);
		Bool excess_significand_ne0 = unpack(excess_significand_msb | excess_significand_rest);

		UInt#(TSub#(`I_SIGNIFICAND_LEN, TSub#(`I_FRACTION_LEN, significand_len))) new_rounded_significand = case (rm) matches
			Rne: case ({ excess_significand_msb, excess_significand_rest }) matches
				2'b00: return rounded_significand;
				2'b01: return rounded_significand;
				2'b10: return rounded_significand + unpack(extend(lsb(rounded_significand)));
				2'b11: return rounded_significand + 1;
			endcase

			Rtz: return rounded_significand;

			Rdn: return sign ? rounded_significand + unpack(extend(pack(excess_significand_ne0))) : rounded_significand;

			Rup: return sign ? rounded_significand : rounded_significand + unpack(extend(pack(excess_significand_ne0)));

			Rmm: return rounded_significand + unpack(extend(excess_significand_msb));
		endcase;

		significand = unpack({ pack(new_rounded_significand), Bit#(TSub#(`I_FRACTION_LEN, significand_len))'('0) });

		// Normalize 1.1111E0 + 1 = 10.0000E0 -> 1.0000XE1
		let significand_ge2 = unpack(| (pack(significand) >> (`I_FRACTION_LEN + 1)));
		if (significand_ge2) begin
			significand = significand >> 1;
			exponent = exponent + 1;
		end
	end

	return tuple2(exponent, significand);
endfunction

function Tuple2#(UInt#(t), Bool) shift_accumulate(UInt#(t) value, s shamt)
provisos (
	Add#(1, a__, t),
	Arith#(s),
	PrimShiftIndex#(s, b__)
);
	if (shamt > 0) begin
		let excess = | (value & ((1 << shamt) - 1));
		value = value >> shamt;
		value = value | extend(excess);
		return tuple2(value, unpack(pack(excess)));
	end else
		return tuple2(value << (-shamt), False);
endfunction

function Tuple2#(Int#(t), Bool) shift_accumulate_i(Int#(t) value, s shamt)
provisos (
	Add#(1, a__, t),
	Arith#(s),
	PrimShiftIndex#(s, b__)
);
	if (shamt > 0) begin
		Bit#(1) excess = | (pack(value) & ((1 << shamt) - 1));
		value = value >> shamt;
		value = value | unpack(extend(excess));
		return tuple2(value, unpack(excess));
	end else
		return tuple2(value << (-shamt), False);
endfunction

typedef Server#(ClassifyRequest, ClassifyResponse) Classify;

typedef struct {
	UnpackedValue arg;
} ClassifyRequest deriving(Bits);

typedef struct {
	Bit#(10) result;
} ClassifyResponse deriving(Bits);

(* synthesize *)
module mkClassify(Classify);
	FIFO#(ClassifyRequest) args_ <- mkBypassFIFO;
	GetS#(ClassifyRequest) args = fifoToGetS(args_);
	FIFO#(ClassifyResponse) result_ <- mkBypassFIFO;
	Put#(ClassifyResponse) result = toPut(result_);

	rule run(args.first matches ClassifyRequest { arg: .arg });
		result.put(ClassifyResponse { result: classify_(arg) });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Bit#(10) classify_(UnpackedValue arg);
	Bit#(10) classify_result = '0;
	case (arg) matches
		tagged Finite { sign: True, significand: .significand }: begin
			Tuple2#(Bit#(`I_INTEGER_LEN), Bit#(`I_FRACTION_LEN)) parts = split(pack(significand));
			match { .significand_integer, .significand_fraction } = parts;
			if (significand_integer == '0)
				if (significand_fraction == '0)
					classify_result[3] = '1;
				else
					classify_result[2] = '1;
			else
				classify_result[1] = '1;
		end

		tagged Finite { sign: False, significand: .significand }: begin
			Tuple2#(Bit#(`I_INTEGER_LEN), Bit#(`I_FRACTION_LEN)) parts = split(pack(significand));
			match { .significand_integer, .significand_fraction } = parts;
			if (significand_integer == '0)
				if (significand_fraction == '0)
					classify_result[4] = '1;
				else
					classify_result[5] = '1;
			else
				classify_result[6] = '1;
		end

		tagged Infinity { sign: True }: classify_result[0] = '1;

		tagged Infinity { sign: False }: classify_result[7] = '1;

		tagged NaN { quiet: True }: classify_result[9] = '1;

		tagged NaN { quiet: False }: classify_result[8] = '1;
	endcase
	return classify_result;
endfunction

typedef Server#(AddRequest, AddResponse) Add;

typedef struct {
	Unpacked arg1;
	UnpackedValue arg2;
	RoundingMode rm;
} AddRequest deriving(Bits);

typedef struct {
	Unpacked result;
} AddResponse deriving(Bits);

(* synthesize *)
module mkAdd(Add);
	FIFO#(AddRequest) args_ <- mkBypassFIFO;
	GetS#(AddRequest) args = fifoToGetS(args_);
	FIFO#(AddResponse) result_ <- mkBypassFIFO;
	Put#(AddResponse) result = toPut(result_);

	rule run(args.first matches AddRequest { arg1: .arg1, arg2: .arg2, rm: .rm });
		result.put(AddResponse { result: add_(arg1, arg2, rm) });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Unpacked add_(Unpacked arg1, UnpackedValue arg2, RoundingMode rm);
	case (tuple2(arg1.value, arg2)) matches
		{
			tagged Finite { sign: .sign1, exponent: .exponent1_, significand: .significand1 },
			tagged Finite { sign: .sign2, exponent: .exponent2_, significand: .significand2 }
		}: begin
			let exponent1 = exponent1_;
			let exponent2 = exponent2_;
			case ({ | pack(significand1), | pack(significand2) }) matches
				2'b01: exponent1 = exponent2;
				2'b10: exponent2 = exponent1;
			endcase

			let preferred_exponent = max(exponent1, exponent2) - 1;
			let arg1_shift_by = preferred_exponent - exponent1;
			let arg2_shift_by = preferred_exponent - exponent2;

			let inexact = arg1.inexact;

			Int#(TAdd#(`I_SIGNIFICAND_LEN, 2)) arg1_significand = unpack(pack(extend(significand1)));
			if (sign1)
				arg1_significand = -arg1_significand;
			match { .arg1_significand_, .inexact1 } = shift_accumulate_i(arg1_significand, arg1_shift_by);
			arg1_significand = arg1_significand_;
			inexact = inexact || inexact1;

			Int#(TAdd#(`I_SIGNIFICAND_LEN, 2)) arg2_significand = unpack(pack(extend(significand2)));
			if (sign2)
				arg2_significand = -arg2_significand;
			match { .arg2_significand_, .inexact2 } = shift_accumulate_i(arg2_significand, arg2_shift_by);
			arg2_significand = arg2_significand_;
			inexact = inexact || inexact2;

			let sum_significand = arg1_significand + arg2_significand;
			// +----+----+-----+-----+-----+-----+-----+
			// | A  | B  | Rne | Rtz | Rdn | Rup | Rmm |
			// +====+====+=====+=====+=====+=====+=====+
			// | +x | +x |  +  |  +  |  +  |  +  |  +  |
			// | +x | -x |  +  |  +  |  -  |  +  |  +  |
			// | -x | +x |  +  |  +  |  -  |  +  |  +  |
			// | -x | -x |  -  |  -  |  -  |  -  |  -  |
			// +----+----+-----+-----+-----+-----+-----+
			let sum_sign =
				(sign1 && sign2) ||
				(sum_significand < 0) ||
				(rm == Rdn && sum_significand == 0 && unpack(pack(sign1) ^ pack(sign2)));
			if (sum_significand < 0)
				sum_significand = -sum_significand;
			match { .normalized_exponent, .normalized_significand, .inexact3 } = normalize_significand(preferred_exponent, unpack(pack(sum_significand)));
			inexact = inexact || inexact3;

			return Unpacked {
				value: tagged Finite {
					sign: sum_sign,
					exponent: normalized_exponent,
					significand: normalized_significand
				},
				inexact: inexact
			};
		end

		{ tagged Finite ._1, tagged Infinity ._2 }:
			return Unpacked { value: arg2, inexact: arg1.inexact };

		{ tagged Finite ._1, tagged NaN ._2 }:
			return Unpacked { value: arg2, inexact: arg1.inexact };

		{ tagged Infinity ._1, tagged Finite ._2 }:
			return arg1;

		{ tagged Infinity { sign: .sign1 }, tagged Infinity { sign: .sign2 } }:
			if (sign1 == sign2)
				return arg1;
			else
				return Unpacked { value: tagged NaN { sign: ?, quiet: False }, inexact: arg1.inexact };

		{ tagged Infinity ._1, tagged NaN ._2 }:
			return Unpacked { value: arg2, inexact: arg1.inexact };

		{ tagged NaN ._1, tagged Finite ._2 }:
			return arg1;

		{ tagged NaN ._1, tagged Infinity ._2 }:
			return arg1;

		{ tagged NaN { quiet: .quiet1 }, tagged NaN { quiet: .quiet2 } }:
			return Unpacked { value: tagged NaN { sign: ?, quiet: quiet1 && quiet2 }, inexact: arg1.inexact };
	endcase
endfunction

typedef Server#(MultiplyRequest, MultiplyResponse) Multiply;

typedef struct {
	UnpackedValue arg1;
	UnpackedValue arg2;
} MultiplyRequest deriving(Bits);

typedef struct {
	Unpacked result;
} MultiplyResponse deriving(Bits);

(* synthesize *)
module mkMultiply(Multiply);
	FIFO#(MultiplyRequest) args_ <- mkBypassFIFO;
	GetS#(MultiplyRequest) args = fifoToGetS(args_);
	FIFO#(MultiplyResponse) result_ <- mkBypassFIFO;
	Put#(MultiplyResponse) result = toPut(result_);

	rule run(args.first matches MultiplyRequest { arg1: .arg1, arg2: .arg2 });
		result.put(MultiplyResponse { result: multiply_(arg1, arg2) });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Unpacked multiply_(UnpackedValue arg1, UnpackedValue arg2);
	case (tuple2(arg1, arg2)) matches
		{
			tagged Finite { sign: .sign1, exponent: .exponent1, significand: .significand1 },
			tagged Finite { sign: .sign2, exponent: .exponent2, significand: .significand2 }
		}: begin
			UInt#(TMul#(`I_SIGNIFICAND_LEN, 2)) arg1_significand = zeroExtend(significand1);
			UInt#(TMul#(`I_SIGNIFICAND_LEN, 2)) arg2_significand = zeroExtend(significand2);

			let product_exponent = exponent1 + exponent2;
			match { .x, .inexact } = shift_accumulate(arg1_significand * arg2_significand, valueOf(`I_FRACTION_LEN));
			UInt#(`I_SIGNIFICAND_LEN) product_significand = truncate(x);
			match { .normalized_exponent, .normalized_significand, .inexact_ } = normalize_significand(product_exponent, product_significand);
			inexact = inexact || inexact_;

			return Unpacked {
				value: tagged Finite {
					sign: unpack(pack(sign1) ^ pack(sign2)),
					exponent: normalized_exponent,
					significand: normalized_significand
				},
				inexact: inexact
			};
		end

		{ tagged Finite { sign: .sign1, significand: .significand }, tagged Infinity { sign: .sign2 } }:
			if (significand == 0)
				return Unpacked { value: tagged NaN { sign: ?, quiet: False }, inexact: False };
			else
				return Unpacked { value: tagged Infinity { sign: unpack(pack(sign1) ^ pack(sign2)) }, inexact: False };

		{ tagged Finite ._1, tagged NaN ._2 }:
			return Unpacked { value: arg2, inexact: False };

		{ tagged Infinity { sign: .sign1 }, tagged Finite { sign: .sign2, significand: .significand } }:
			if (significand == 0)
				return Unpacked { value: tagged NaN { sign: ?, quiet: False }, inexact: False };
			else
				return Unpacked { value: tagged Infinity { sign: unpack(pack(sign1) ^ pack(sign2)) }, inexact: False };

		{ tagged Infinity { sign: .sign1 }, tagged Infinity { sign: .sign2 } }:
			return Unpacked { value: tagged Infinity { sign: unpack(pack(sign1) ^ pack(sign2)) }, inexact: False };

		{ tagged Infinity ._1, tagged NaN ._2 }:
			return Unpacked { value: arg2, inexact: False };

		{ tagged NaN ._1, tagged Finite ._2 }:
			return Unpacked { value: arg1, inexact: False };

		{ tagged NaN ._1, tagged Infinity ._2 }:
			return Unpacked { value: arg1, inexact: False };

		{ tagged NaN { quiet: .quiet1 }, tagged NaN { quiet: .quiet2 } }:
			return Unpacked { value: tagged NaN { sign: ?, quiet: quiet1 && quiet2 }, inexact: False };
	endcase
endfunction

typedef Server#(SignInjectRequest, SignInjectResponse) SignInject;

typedef struct {
	SignInjectOp op;
	Width width;
	Packed arg1;
	Packed arg2;
} SignInjectRequest deriving(Bits);

typedef struct {
	Packed result;
} SignInjectResponse deriving(Bits);

(* synthesize *)
module mkSignInject(SignInject);
	FIFO#(SignInjectRequest) args_ <- mkBypassFIFO;
	GetS#(SignInjectRequest) args = fifoToGetS(args_);
	FIFO#(SignInjectResponse) result_ <- mkBypassFIFO;
	Put#(SignInjectResponse) result = toPut(result_);

	rule run(args.first matches SignInjectRequest { op: .op, width: .width, arg1: .arg1, arg2: .arg2 });
		let arg1_sign_injected = case (width) matches
			H: begin
				UnpackedValueInner#(`H_EXPONENT_LEN, `H_SIGNIFICAND_LEN) arg2_unpacked = unpack_inner1(arg2);
				let arg2_sign =
					(arg2_unpacked.upper == '1) ?
						arg2_unpacked.sign :
						'0; // Canonical NaN's sign

				UnpackedValueInner#(`H_EXPONENT_LEN, `H_SIGNIFICAND_LEN) arg1_unpacked = unpack_inner1(arg1);
				if (arg1_unpacked.upper != '1) begin
					// Canonical NaN
					arg1_unpacked.upper = '1;
					arg1_unpacked.sign = '0;
					arg1_unpacked.exponent = '1;
					arg1_unpacked.significand = { 1'b1, '0 };
				end

				let arg1_new_sign = sign_inject_(op, arg1_unpacked.sign, arg2_sign);
				return { arg1_unpacked.upper, arg1_new_sign, arg1_unpacked.exponent, arg1_unpacked.significand };
			end

			S: begin
				UnpackedValueInner#(`S_EXPONENT_LEN, `S_SIGNIFICAND_LEN) arg2_unpacked = unpack_inner1(arg2);
				let arg2_sign =
					(arg2_unpacked.upper == '1) ?
						arg2_unpacked.sign :
						'0; // Canonical NaN's sign

				UnpackedValueInner#(`S_EXPONENT_LEN, `S_SIGNIFICAND_LEN) arg1_unpacked = unpack_inner1(arg1);
				if (arg1_unpacked.upper != '1) begin
					// Canonical NaN
					arg1_unpacked.upper = '1;
					arg1_unpacked.sign = '0;
					arg1_unpacked.exponent = '1;
					arg1_unpacked.significand = { 1'b1, '0 };
				end

				let arg1_new_sign = sign_inject_(op, arg1_unpacked.sign, arg2_sign);
				return { arg1_unpacked.upper, arg1_new_sign, arg1_unpacked.exponent, arg1_unpacked.significand };
			end

			D: begin
				UnpackedValueInner#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN) arg2_unpacked = unpack_inner1(arg2);
				let arg2_sign = arg2_unpacked.sign;

				UnpackedValueInner#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN) arg1_unpacked = unpack_inner1(arg1);

				let arg1_new_sign = sign_inject_(op, arg1_unpacked.sign, arg2_sign);
				return { arg1_unpacked.upper, arg1_new_sign, arg1_unpacked.exponent, arg1_unpacked.significand };
			end
		endcase;
		result.put(SignInjectResponse { result: arg1_sign_injected });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Bit#(1) sign_inject_(SignInjectOp op, Bit#(1) arg1_sign, Bit#(1) arg2_sign);
	case (op) matches
		Sgnj: return arg2_sign;
		Sgnjn: return ~arg2_sign;
		Sgnjx: return arg1_sign ^ arg2_sign;
	endcase
endfunction

typedef Server#(SqrtRequest, SqrtResponse) Sqrt;

typedef struct {
	UnpackedValue arg;
} SqrtRequest deriving(Bits);

typedef struct {
	Unpacked result;
} SqrtResponse deriving(Bits);

(* synthesize *)
module mkSqrt(Sqrt);
	FIFO#(SqrtRequest) args_ <- mkBypassFIFO;
	GetS#(SqrtRequest) args = fifoToGetS(args_);
	FIFO#(SqrtResponse) result_ <- mkBypassFIFO;
	Put#(SqrtResponse) result = toPut(result_);

	rule run(args.first matches SqrtRequest { arg: .arg });
		result.put(SqrtResponse { result: sqrt_(arg) });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Unpacked sqrt_(UnpackedValue arg);
	case (arg) matches
		tagged Finite { sign: .sign, exponent: .exponent, significand: .significand }:
			if (significand == 0)
				return Unpacked { value: arg, inexact: False };
			else if (sign)
				return Unpacked { value: tagged NaN { sign: False, quiet: False }, inexact: False };
			else begin
				Bit#(TAdd#(`I_SIGNIFICAND_LEN, `I_SIGNIFICAND_LEN)) a = extend(pack(significand));
				if (lsb(exponent) != 0)
					a = a << 1;
				Bit#(`I_SIGNIFICAND_LEN) r = '1;

				for (Integer i = 0; i < valueOf(`I_SIGNIFICAND_LEN); i = i + 1) begin
					Tuple2#(Bit#(TAdd#(`I_SIGNIFICAND_LEN, 2)), Bit#(TSub#(`I_SIGNIFICAND_LEN, 2))) a_parts = split(a);
					match { .a_upper, .a_lower } = a_parts;
					Bit#(TAdd#(`I_SIGNIFICAND_LEN, 2)) a_upper_next = a_upper + { r, 2'b11 };
					r = (r << 1) | extend(msb(a_upper_next));
					a = {
						unpack(msb(a_upper_next)) ? truncate(a_upper) : truncate(a_upper_next),
						a_lower,
						2'b00
					};
				end

				return Unpacked {
					value: tagged Finite {
						sign: sign,
						exponent: (exponent >> 1) - 1,
						significand: unpack(~r) | extend(unpack(pack(a != 0)))
					},
					inexact: a != 0
				};
			end

		tagged Infinity { sign: .sign }:
			if (sign)
				return Unpacked { value: tagged NaN { sign: False, quiet: False }, inexact: False };
			else
				return Unpacked { value: arg, inexact: False };

		tagged NaN { sign: .sign, quiet: .quiet }:
			return Unpacked { value: arg, inexact: False };
	endcase
endfunction

`ifdef TESTING
import BuildVector::*;
import StmtFSM::*;
import Vector::*;

typedef struct {
	RvFpuRequest request;
	RvFpuResponse expected_response;
} TestCase;
`endif
