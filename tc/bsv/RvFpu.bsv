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

`define I_EXPONENT_LEN 15
`define I_INTEGER_LEN 4
`define I_FRACTION_LEN 60
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
} Flags;

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
} Unpacked;

instance Bits#(Unpacked, TAdd#(1, TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN)));
	function Bit#(TAdd#(1, TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN))) pack(Unpacked value);
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

	function Unpacked unpack(Bit#(TAdd#(1, TAdd#(`I_EXPONENT_LEN, `I_SIGNIFICAND_LEN))) bits);
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

Unpacked canonical_nan = tagged NaN { sign: False, quiet: True };

typedef Server#(RvFpuRequest, RvFpuResponse) RvFpu;

typedef union tagged {
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
	} Multiply;

	struct {
		SignInjectOp op;
		Width width;
		Packed arg1;
		Packed arg2;
	} SignInject;
} RvFpuRequest deriving(Bits, FShow);

typedef struct {
	Packed result;
} RvFpuResponse deriving(Bits, Eq);

typedef enum {
	Sgnj,
	Sgnjn,
	Sgnjx
} SignInjectOp deriving(Bits, FShow);

(* synthesize *)
module mkRvFpu(RvFpu);
	Unpack unpack_arg1 <- mkUnpack;
	Unpack unpack_arg2 <- mkUnpack;
	Classify classifier <- mkClassify;
	Multiply multiplier <- mkMultiply;
	SignInject sign_injector <- mkSignInject;
	Pack pack_result <- mkPack;

	FIFO#(RvFpuRequest) args_ <- mkBypassFIFO;
	GetS#(RvFpuRequest) args = fifoToGetS(args_);
	FIFO#(RvFpuResponse) result_ <- mkBypassFIFO;
	Put#(RvFpuResponse) result = toPut(result_);

	rule classify_1(args.first matches tagged Classify { width: .width, arg: .arg });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg });
	endrule

	rule classify_2(args.first matches tagged Classify ._);
		match UnpackResponse { value: .value } = unpack_arg1.response.first;
		classifier.request.put(ClassifyRequest { arg: value });
	endrule

	rule classify_end(args.first matches tagged Classify ._);
		match ClassifyResponse { result: .value } = classifier.response.first;
		result.put(RvFpuResponse { result: extend(value) });
	endrule

	rule convert_1(args.first matches tagged Convert { in: .width, arg: .arg });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg });
	endrule

	rule convert_2(args.first matches tagged Convert { rm: .rm, out: .width });
		match UnpackResponse { value: .value } = unpack_arg1.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: value });
	endrule

	rule convert_end(args.first matches tagged Convert ._);
		match PackResponse { result: .packed_ } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_ });
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
		match MultiplyResponse { result: .product } = multiplier.response.first;
		pack_result.request.put(PackRequest { width: width, rm: rm, value: product });
	endrule

	rule multiply_end(args.first matches tagged Multiply ._);
		match PackResponse { result: .packed_ } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_ });
	endrule

	rule sign_inject_1(args.first matches tagged SignInject { width: .width, arg1: .arg1, arg2: .arg2 });
		unpack_arg1.request.put(UnpackRequest { width: width, value: arg1 });
		unpack_arg2.request.put(UnpackRequest { width: width, value: arg2 });
	endrule

	rule sign_inject_2(args.first matches tagged SignInject { op: .op, width: .width });
		match UnpackResponse { value: .arg1 } = unpack_arg1.response.first;
		match UnpackResponse { value: .arg2 } = unpack_arg2.response.first;
		sign_injector.request.put(SignInjectRequest { op: op, arg1: arg1, arg2: arg2 });
	endrule

	rule sign_inject_3(args.first matches tagged SignInject { width: .width });
		match SignInjectResponse { result: .sign_inject_result } = sign_injector.response.first;
		pack_result.request.put(PackRequest { width: width, rm: ?, value: sign_inject_result });
	endrule

	rule sign_inject_end(args.first matches tagged SignInject ._);
		match PackResponse { result: .packed_ } = pack_result.response.first;
		result.put(RvFpuResponse { result: packed_ });
	endrule

	interface request = toPut(args_);

	interface GetS response;
		method RvFpuResponse first = result_.first;

		method Action deq;
			args_.deq;

			case (args.first) matches
				tagged Classify ._: begin
					unpack_arg1.response.deq;
					classifier.response.deq;
				end

				tagged Convert ._: begin
					unpack_arg1.response.deq;
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
			endcase

			result_.deq;
		endmethod
	endinterface
endmodule

typedef Server#(UnpackRequest, UnpackResponse) Unpack;

typedef struct {
	Width width;
	Packed value;
} UnpackRequest deriving(Bits);

typedef struct {
	Unpacked value;
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
} UnpackedInner#(numeric type exponent_len, numeric type significand_len);

function Unpacked unpack_(Width width, Packed value);
	case (width) matches
		H: begin
			UnpackedInner#(`H_EXPONENT_LEN, `H_SIGNIFICAND_LEN) unpacked = unpack_inner1(value);
			return unpack_inner2(unpacked);
		end
		S: begin
			UnpackedInner#(`S_EXPONENT_LEN, `S_SIGNIFICAND_LEN) unpacked = unpack_inner1(value);
			return unpack_inner2(unpacked);
		end
		D: begin
			UnpackedInner#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN) unpacked = unpack_inner1(value);
			return unpack_inner2(unpacked);
		end
	endcase
endfunction

function UnpackedInner#(exponent_len, significand_len) unpack_inner1(Packed value);
	let exponent_len = valueOf(exponent_len);
	let significand_len = valueOf(significand_len);

	let lower_len = 1 + exponent_len + significand_len;
	let upper_len = valueOf(SizeOf#(Packed)) - lower_len;

	Tuple2#(Bit#(TSub#(SizeOf#(Packed), lower_len)), Bit#(lower_len)) parts0 = split(value);
	match { .upper, .lower } = parts0;

	Tuple2#(Bit#(1), Bit#(TAdd#(exponent_len, significand_len))) parts1 = split(lower);
	match { .sign, .rest } = parts1;

	Tuple2#(Bit#(exponent_len), Bit#(significand_len)) parts2 = split(rest);
	match { .exponent, .significand } = parts2;

	return UnpackedInner {
		upper: upper,
		sign: sign,
		exponent: exponent,
		significand: significand
	};
endfunction

function Unpacked unpack_inner2(UnpackedInner#(exponent_len, significand_len) value)
provisos (
	Add#(exponent_len, a__, `I_EXPONENT_LEN),
	Add#(significand_len, b__, `I_FRACTION_LEN)
);
	let exponent_len = valueOf(exponent_len);
	let significand_len = valueOf(significand_len);
	let lower_len = 1 + exponent_len + significand_len;
	let upper_len = valueOf(SizeOf#(Packed)) - lower_len;

	match UnpackedInner { upper: .upper, sign: .sign, exponent: .exponent, significand: .significand } = value;

	if (upper_len == 0 || upper == '1) begin
		let bias = (1 << (exponent_len - 1)) - 1;

		case ({ & exponent, | significand }) matches
			2'b11: return tagged NaN { sign: unpack(sign), quiet: unpack(msb(significand)) };

			2'b10: return tagged Infinity { sign: unpack(sign) };

			// Finite
			default: begin
				// 1.significand_len
				Bit#(TAdd#(1, significand_len)) significand_a = { | exponent, significand };
				// 1.I_FRACTION_LEN
				Bit#(TAdd#(1, `I_FRACTION_LEN)) significand_b = { significand_a, '0 };
				// I_INTEGER_LEN.I_FRACTION_LEN
				Bit#(`I_SIGNIFICAND_LEN) significand_c = extend(significand_b);
				return tagged Finite {
					sign: unpack(sign),
					exponent: (unpack(| exponent) ? unpack(extend(exponent)) : 1) - bias,
					significand: unpack(significand_c)
				};
			end
		endcase
	end else
		// Not boxed correctly.
		return canonical_nan;
endfunction

typedef Server#(PackRequest, PackResponse) Pack;

typedef struct {
	Width width;
	RoundingMode rm;
	Unpacked value;
} PackRequest deriving(Bits);

typedef struct {
	Packed result;
} PackResponse deriving(Bits);

(* synthesize *)
module mkPack(Pack);
	FIFO#(PackRequest) args_ <- mkBypassFIFO;
	GetS#(PackRequest) args = fifoToGetS(args_);
	FIFO#(PackResponse) result_ <- mkBypassFIFO;
	Put#(PackResponse) result = toPut(result_);

	rule run(args.first matches PackRequest { width: .width, rm: .rm, value: .value });
		case (width) matches
			H: begin
				UnpackedInner#(`H_EXPONENT_LEN, `H_SIGNIFICAND_LEN) rounded_value = round(rm, value);
				result.put(PackResponse { result: {
					rounded_value.upper,
					pack(rounded_value.sign),
					rounded_value.exponent,
					rounded_value.significand
				} });
			end

			S: begin
				UnpackedInner#(`S_EXPONENT_LEN, `S_SIGNIFICAND_LEN) rounded_value = round(rm, value);
				result.put(PackResponse { result: {
					rounded_value.upper,
					pack(rounded_value.sign),
					rounded_value.exponent,
					rounded_value.significand
				} });
			end

			D: begin
				UnpackedInner#(`D_EXPONENT_LEN, `D_SIGNIFICAND_LEN) rounded_value = round(rm, value);
				result.put(PackResponse { result: {
					rounded_value.upper,
					pack(rounded_value.sign),
					rounded_value.exponent,
					rounded_value.significand
				} });
			end
		endcase
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function UnpackedInner#(exponent_len, significand_len) round(RoundingMode rm, Unpacked value)
provisos (
	Add#(exponent_len, a__, `I_EXPONENT_LEN),
	Add#(1, b__, exponent_len),
	Add#(1, TAdd#(1, c__), significand_len),
	Add#(significand_len, d__, `I_FRACTION_LEN)
);
	let exponent_len = valueOf(exponent_len);
	let significand_len = valueOf(significand_len);

	let bias = (1 << (exponent_len - 1)) - 1;
	Int#(`I_EXPONENT_LEN) normal_exponent_max = bias;

	// Initial normalize
	if (value matches tagged Finite { sign: .sign, exponent: .exponent, significand: .significand }) begin
		match { .normalized_exponent, .normalized_significand } = normalize_finite(exponent_len, significand_len, exponent, significand);
		value = tagged Finite { sign: sign, exponent: normalized_exponent, significand: normalized_significand };
	end

	// Round
	if (value matches tagged Finite { sign: .sign, exponent: .exponent_, significand: .significand_ }) begin
		let exponent = exponent_;
		UInt#(`I_SIGNIFICAND_LEN) significand = significand_;

		Tuple2#(
			Bit#(TSub#(`I_SIGNIFICAND_LEN, TSub#(`I_FRACTION_LEN, significand_len))),
			Bit#(TSub#(`I_FRACTION_LEN, significand_len))
		) significand_parts = split(pack(significand));
		match { .rounded_significand_, .excess_significand } = significand_parts;
		UInt#(TSub#(`I_SIGNIFICAND_LEN, TSub#(`I_FRACTION_LEN, significand_len))) rounded_significand = unpack(rounded_significand_);

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

		significand = unpack({ pack(new_rounded_significand), '0 });

		// Normalize 1.1111E0 + 1 = 10.0000E0 -> 1.0000XE1
		begin
			let significand_ge2 = unpack(| (pack(significand) >> (`I_FRACTION_LEN + 1)));
			if (significand_ge2) begin
				let excess_significand = | (significand & 1);
				significand = significand >> 1;
				significand = significand | extend(excess_significand);
				exponent = exponent + 1;
				value = tagged Finite { sign: sign, exponent: exponent, significand: significand };
			end else
				value = tagged Finite { sign: sign, exponent: exponent, significand: significand };
		end
	end

	case (value) matches
		tagged Finite { sign: .sign, exponent: .exponent, significand: .significand }: begin
			Tuple2#(
				Bit#(TSub#(`I_SIGNIFICAND_LEN, TSub#(`I_FRACTION_LEN, significand_len))),
				Bit#(TSub#(`I_FRACTION_LEN, significand_len))
			) significand_parts = split(pack(significand));
			match { .rounded_significand_, .excess_significand } = significand_parts;
			UInt#(TSub#(`I_SIGNIFICAND_LEN, TSub#(`I_FRACTION_LEN, significand_len))) rounded_significand = unpack(rounded_significand_);

			if (exponent > normal_exponent_max) begin
				let infinity = UnpackedInner {
					upper: '1,
					sign: pack(sign),
					exponent: '1,
					significand: '0
				};
				let finite_max = UnpackedInner {
					upper: '1,
					sign: pack(sign),
					exponent: { '1, 1'b0 },
					significand: '1
				};
				case (rm) matches
					Rne: return infinity;
					Rtz: return finite_max;
					Rdn: return sign ? infinity : finite_max;
					Rup: return sign ? finite_max : infinity;
					Rmm: return infinity;
				endcase
			end else begin
				let significand_lt1 = unpack(~| (pack(significand) >> `I_FRACTION_LEN));
				if (significand_lt1)
					// Zero or subnormal
					return UnpackedInner {
						upper: '1,
						sign: pack(sign),
						exponent: '0,
						significand: truncate(rounded_significand_)
					};

				else
					// Normal
					return UnpackedInner {
						upper: '1,
						sign: pack(sign),
						exponent: truncate(pack(exponent + bias)),
						significand: truncate(rounded_significand_)
					};
			end
		end

		tagged Infinity { sign: .sign }: return UnpackedInner {
			upper: '1,
			sign: pack(sign),
			exponent: '1,
			significand: '0
		};

		// Canonical NaN
		tagged NaN ._: return UnpackedInner {
			upper: '1,
			sign: '0,
			exponent: '1,
			significand: { 1'b1, '0 }
		};
	endcase
endfunction

function Tuple2#(Int#(`I_EXPONENT_LEN), UInt#(`I_SIGNIFICAND_LEN)) normalize_finite(
	Integer exponent_len,
	Integer significand_len,
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
	Int#(`I_EXPONENT_LEN) subnormal_exponent = -bias;
	Int#(`I_EXPONENT_LEN) normal_exponent_min = -bias + 1;
	Int#(`I_EXPONENT_LEN) normal_exponent_max = bias;

	Int#(`I_EXPONENT_LEN) shift_by_min_for_exponent = normal_exponent_min - exponent;
	if (shift_by_min_for_exponent > 0) begin
		// 1e-20 -> 0.1e-19 until Xe-14

		let shift_by = shift_by_min_for_exponent;
		let excess_significand = | (significand & ((1 << shift_by) - 1));
		significand = significand >> shift_by;
		significand = significand | extend(excess_significand);
		exponent = normal_exponent_min;
	end

	let leading_zeros = countZerosMSB(pack(significand));
	let significand_ne0 = unpack(| pack(significand));

	if (significand_ne0) begin
		Int#(`I_EXPONENT_LEN) shift_by = (`I_INTEGER_LEN - 1) - unpack(pack(extend(leading_zeros)));
		Int#(`I_EXPONENT_LEN) shift_by_max_for_exponent = normal_exponent_max - exponent;
		Int#(`I_EXPONENT_LEN) shift_by_min_for_exponent = normal_exponent_min - exponent;

		case (compare(shift_by, 0)) matches
			// 0.1e1 -> 1e0 until 1eX or Xe-14
			LT: begin
				shift_by = max(shift_by, shift_by_min_for_exponent);
				significand = significand << (-shift_by);
				exponent = exponent + shift_by;
			end

			// 2e19 -> 1e20 until 1eX
			GT: begin
				let excess_significand = | (significand & ((1 << shift_by) - 1));
				significand = significand >> shift_by;
				significand = significand | extend(excess_significand);
				exponent = exponent + shift_by;
			end
		endcase

		return tuple2(exponent, significand);

	end else
		// Zero
		return tuple2(?, significand);
endfunction

typedef Server#(ClassifyRequest, ClassifyResponse) Classify;

typedef struct {
	Unpacked arg;
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

function Bit#(10) classify_(Unpacked arg);
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

typedef Server#(MultiplyRequest, MultiplyResponse) Multiply;

typedef struct {
	Unpacked arg1;
	Unpacked arg2;
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

function Unpacked multiply_(Unpacked arg1, Unpacked arg2);
	case (tuple2(arg1, arg2)) matches
		{
			tagged Finite { sign: .sign1, exponent: .exponent1, significand: .significand1 },
			tagged Finite { sign: .sign2, exponent: .exponent2, significand: .significand2 }
		}: begin
			UInt#(TMul#(`I_SIGNIFICAND_LEN, 2)) arg1_significand = zeroExtend(significand1);
			UInt#(TMul#(`I_SIGNIFICAND_LEN, 2)) arg2_significand = zeroExtend(significand2);
			return tagged Finite {
				sign: unpack(pack(sign1) ^ pack(sign2)),
				exponent: exponent1 + exponent2,
				significand: truncate((arg1_significand * arg2_significand) >> valueOf(`I_FRACTION_LEN))
			};
		end

		{ tagged Finite { sign: .sign1 }, tagged Infinity { sign: .sign2 } }:
			return tagged Infinity { sign: unpack(pack(sign1) ^ pack(sign2)) };

		{ tagged Finite ._1, tagged NaN ._2 }:
			return canonical_nan;

		{ tagged Infinity { sign: .sign1 }, tagged Finite { sign: .sign2 } }:
			return tagged Infinity { sign: unpack(pack(sign1) ^ pack(sign2)) };

		{ tagged Infinity { sign: .sign1 }, tagged Infinity { sign: .sign2 } }:
			return tagged Infinity { sign: unpack(pack(sign1) ^ pack(sign2)) };

		{ tagged Infinity ._1, tagged NaN ._2 }:
			return canonical_nan;

		{ tagged NaN ._1, tagged Finite ._2 }:
			return canonical_nan;

		{ tagged NaN ._1, tagged Infinity ._2 }:
			return canonical_nan;

		{ tagged NaN ._1, tagged NaN ._2 }:
			return canonical_nan;
	endcase
endfunction

typedef Server#(SignInjectRequest, SignInjectResponse) SignInject;

typedef struct {
	SignInjectOp op;
	Unpacked arg1;
	Unpacked arg2;
} SignInjectRequest deriving(Bits);

typedef struct {
	Unpacked result;
} SignInjectResponse deriving(Bits);

(* synthesize *)
module mkSignInject(SignInject);
	FIFO#(SignInjectRequest) args_ <- mkBypassFIFO;
	GetS#(SignInjectRequest) args = fifoToGetS(args_);
	FIFO#(SignInjectResponse) result_ <- mkBypassFIFO;
	Put#(SignInjectResponse) result = toPut(result_);

	rule run(args.first matches SignInjectRequest { op: .op, arg1: .arg1, arg2: .arg2 });
		result.put(SignInjectResponse { result: sign_inject_(op, arg1, arg2) });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Unpacked sign_inject_(SignInjectOp op, Unpacked arg1, Unpacked arg2);
	let sign1 = case (arg1) matches
		tagged Finite { sign: .sign }: return sign;
		tagged Infinity { sign: .sign }: return sign;
		tagged NaN { sign: .sign }: return sign;
	endcase;

	let sign2 = case (arg2) matches
		tagged Finite { sign: .sign }: return sign;
		tagged Infinity { sign: .sign }: return sign;
		tagged NaN { sign: .sign }: return sign;
	endcase;

	let injected_sign = case (op) matches
		Sgnj: return sign2;
		Sgnjn: return !sign2;
		Sgnjx: return unpack(pack(sign1) ^ pack(sign2));
	endcase;

	case (arg1) matches
		tagged Finite { sign: .sign, exponent: .exponent, significand: .significand }:
			return tagged Finite { sign: injected_sign, exponent: exponent, significand: significand };
		tagged Infinity { sign: .sign }:
			return tagged Infinity { sign: injected_sign };
		tagged NaN { sign: .sign, quiet: .quiet }:
			return tagged NaN { sign: injected_sign, quiet: quiet };
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
