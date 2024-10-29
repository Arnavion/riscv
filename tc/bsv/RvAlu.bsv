import Vector::*;

import RvCommon::*;
import RvDecoder::*;

interface RvAlu;
	method ExecuteResult execute(
		Int#(64) pc,
		Int#(64) next_pc,
		Instruction#(Int#(64), Csr, Int#(64)) inst
	);
endinterface

typedef union tagged {
	void Efault;
	void Sigill;
	ExecuteResultOk Ok;
} ExecuteResult deriving(Bits);

typedef struct {
	XReg x_regs_rd;
	Int#(64) x_regs_rd_value;
	Maybe#(Tuple2#(Csr, Int#(64))) csrd;
	Maybe#(Int#(64)) jump_pc;
} ExecuteResultOk deriving(Bits);

(* synthesize *)
module mkRvAlu(RvAlu);
	Adder adder <- mkAdder;
	Cmp cmp <- mkCmp;
	Logical logical <- mkLogical;
	OrcB orc_b <- mkOrcB;
	Popcnt popcnt <- mkPopcnt;
	ShiftRotate shift_rotate <- mkShiftRotate;

	method ExecuteResult execute(
		Int#(64) pc,
		Int#(64) next_pc,
		Instruction#(Int#(64), Csr, Int#(64)) inst
	);
		match { .adder_a, .adder_b, .adder_cin } = case (inst) matches
			tagged Auipc { imm: .imm }:
				return tuple3(pc, extend(imm) << 12, False);

			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }: begin
				Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));

				case (op) matches
					tagged Add: return tuple3(rs1, rs2, False);
					tagged AddUw: return tuple3(rs1uw, rs2, False);
					tagged Addw: return tuple3(rs1, rs2, False);
					tagged Sh1add: return tuple3(rs1 << 1, rs2, False);
					tagged Sh1addUw: return tuple3(rs1uw << 1, rs2, False);
					tagged Sh2add: return tuple3(rs1 << 2, rs2, False);
					tagged Sh2addUw: return tuple3(rs1uw << 2, rs2, False);
					tagged Sh3add: return tuple3(rs1 << 3, rs2, False);
					tagged Sh3addUw: return tuple3(rs1uw << 3, rs2, False);
					tagged Sub: return tuple3(rs1, ~rs2, True);
					tagged Subw: return tuple3(rs1, ~rs2, True);
					default: return ?;
				endcase
			end

			tagged Branch { imm: .imm }:
				return tuple3(pc, extend(imm) << 1, False);

			tagged Jal { op: tagged Pc { offset: .offset } }:
				return tuple3(pc, extend(offset) << 1, False);

			tagged Jal { op: tagged XReg { base: .base, offset: .offset } }:
				return tuple3(base, extend(offset), False);

			tagged Unary { op: .op, rs: .rs }:
				case (op) matches
					tagged Clz: return tuple3(unpack(reverseBits(pack(rs))), -1, False);
					tagged Clzw: return tuple3(unpack(reverseBits(pack(rs))), -1, False);
					tagged Ctz: return tuple3(rs, -1, False);
					tagged Ctzw: return tuple3(rs, -1, False);
					default: return ?;
				endcase

			default: return ?;
		endcase;
		let add_result = adder.run(adder_a, adder_b, adder_cin);

		match { .cmp_a, .cmp_b, .cmp_signed } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
					tagged CzeroEqz: return tuple3(0, rs2, ?);
					tagged CzeroNez: return tuple3(0, rs2, ?);
					tagged Max: return tuple3(rs1, rs2, True);
					tagged Maxu: return tuple3(rs1, rs2, False);
					tagged Min: return tuple3(rs1, rs2, True);
					tagged Minu: return tuple3(rs1, rs2, False);
					tagged Slt: return tuple3(rs1, rs2, True);
					tagged Sltu: return tuple3(rs1, rs2, False);
					default: return ?;
				endcase

			tagged Branch { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
					tagged Equal: return tuple3(rs1, rs2, ?);
					tagged NotEqual: return tuple3(rs1, rs2, ?);
					tagged LessThan: return tuple3(rs1, rs2, True);
					tagged GreaterThanOrEqual: return tuple3(rs1, rs2, True);
					tagged LessThanUnsigned: return tuple3(rs1, rs2, False);
					tagged GreaterThanOrEqualUnsigned: return tuple3(rs1, rs2, False);
				endcase

			default: return ?;
		endcase;
		let cmp_result = cmp.cmp(cmp_a, cmp_b, cmp_signed);

		match { .logical_arg1, .logical_arg2, .logical_invert_arg2 } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }: begin
				UInt#(64) rs2u = unpack(pack(rs2));
				UInt#(6) rs2_shamt = truncate(rs2u);
				Int#(64) rs2_decoded = 1 << rs2_shamt;

				case (op) matches
					tagged And: return tuple3(rs1, rs2, False);
					tagged Andn: return tuple3(rs1, rs2, True);
					tagged Bclr: return tuple3(rs1, rs2_decoded, True);
					tagged Binv: return tuple3(rs1, rs2_decoded, False);
					tagged Bset: return tuple3(rs1, rs2_decoded, False);
					tagged Or: return tuple3(rs1, rs2, False);
					tagged Orn: return tuple3(rs1, rs2, True);
					tagged Xnor: return tuple3(rs1, rs2, True);
					tagged Xor: return tuple3(rs1, rs2, False);
					default: return ?;
				endcase
			end

			tagged Csr .op:
				case (op) matches
					tagged Csrrs { rs1: .rs1, csrs: .csrs }: return tuple3(csrs, rs1, False);
					tagged Csrrc { rs1: .rs1, csrs: .csrs }: return tuple3(csrs, rs1, True);
					default: return ?;
				endcase

			tagged Unary { op: .op, rs: .rs }:
				case (op) matches
					tagged Clz: return tuple3(add_result.add, unpack(reverseBits(pack(rs))), True);
					tagged Clzw: return tuple3(add_result.add, unpack(reverseBits(pack(rs))), True);
					tagged Ctz: return tuple3(add_result.add, rs, True);
					tagged Ctzw: return tuple3(add_result.add, rs, True);
					default: return ?;
				endcase

			default: return ?;
		endcase;
		let logical_result = logical.run(logical_arg1, logical_arg2, logical_invert_arg2);

		let popcnt_arg = case (inst) matches
			tagged Unary { op: .op, rs: .rs }:
				case (op) matches
					tagged Clz: return logical_result.and_;
					tagged Clzw: return logical_result.and_;
					tagged Cpop: return rs;
					tagged Cpopw: return rs;
					tagged Ctz: return logical_result.and_;
					tagged Ctzw: return logical_result.and_;
					default: return ?;
				endcase

			default: return ?;
		endcase;
		let popcnt_result = popcnt.run(popcnt_arg);

		match { .shift_rotate_value, .shift_rotate_shamt, .shift_rotate_right, .shift_rotate_rotate, .shift_rotate_arithmetic, .shift_rotate_w } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }: begin
				Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));

				case (op) matches
					tagged Bext: return tuple6(rs1, rs2, True, ?, ?, ?);
					tagged Rol: return tuple6(rs1, rs2, False, True, ?, False);
					tagged Rolw: return tuple6(rs1, rs2, False, True, ?, True);
					tagged Ror: return tuple6(rs1, rs2, True, True, ?, False);
					tagged Rorw: return tuple6(rs1, rs2, True, True, ?, True);
					tagged Sll: return tuple6(rs1, rs2, False, False, ?, False);
					tagged SllUw: return tuple6(rs1uw, rs2, False, False, ?, False);
					tagged Sllw: return tuple6(rs1, rs2, False, False, ?, True);
					tagged Sra: return tuple6(rs1, rs2, True, False, True, False);
					tagged Sraw: return tuple6(rs1, rs2, True, False, True, True);
					tagged Srl: return tuple6(rs1, rs2, True, False, False, False);
					tagged Srlw: return tuple6(rs1, rs2, True, False, False, True);
					default: return ?;
				endcase
			end

			default: return ?;
		endcase;
		let shift_rotate_result = shift_rotate.run(shift_rotate_value, shift_rotate_shamt, shift_rotate_right, shift_rotate_rotate, shift_rotate_arithmetic, shift_rotate_w);

		case (inst) matches
			tagged Auipc { rd: .rd }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: add_result.add,
					csrd: tagged Invalid,
					jump_pc: tagged Invalid
				};

			tagged Binary { op: .op, rd: .rd, rs1: .rs1, rs2: .rs2 }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: case (op) matches
						tagged Add: return add_result.add;
						tagged AddUw: return add_result.add;
						tagged Addw: return add_result.addw;
						tagged And: return logical_result.and_;
						tagged Andn: return logical_result.and_;
						tagged Bclr: return logical_result.and_;
						tagged Bext: return shift_rotate_result & 1;
						tagged Binv: return logical_result.xor_;
						tagged Bset: return logical_result.or_;
						tagged CzeroEqz: return cmp_result.eq ? 0 : rs1;
						tagged CzeroNez: return cmp_result.eq ? rs1 : 0;
						tagged Max: return cmp_result.lt ? rs2 : rs1;
						tagged Maxu: return cmp_result.lt ? rs2 : rs1;
						tagged Min: return cmp_result.lt ? rs1 : rs2;
						tagged Minu: return cmp_result.lt ? rs1 : rs2;
						tagged Or: return logical_result.or_;
						tagged Orn: return logical_result.or_;
						tagged Rol: return shift_rotate_result;
						tagged Rolw: return shift_rotate_result;
						tagged Ror: return shift_rotate_result;
						tagged Rorw: return shift_rotate_result;
						tagged Sh1add: return add_result.add;
						tagged Sh1addUw: return add_result.add;
						tagged Sh2add: return add_result.add;
						tagged Sh2addUw: return add_result.add;
						tagged Sh3add: return add_result.add;
						tagged Sh3addUw: return add_result.add;
						tagged Sll: return shift_rotate_result;
						tagged SllUw: return shift_rotate_result;
						tagged Sllw: return shift_rotate_result;
						tagged Slt: return cmp_result.lt ? 1 : 0;
						tagged Sltu: return cmp_result.lt ? 1 : 0;
						tagged Sra: return shift_rotate_result;
						tagged Sraw: return shift_rotate_result;
						tagged Srl: return shift_rotate_result;
						tagged Srlw: return shift_rotate_result;
						tagged Sub: return add_result.add;
						tagged Subw: return add_result.addw;
						tagged Xnor: return logical_result.xor_;
						tagged Xor: return logical_result.xor_;
					endcase,
					csrd: tagged Invalid,
					jump_pc: tagged Invalid
				};

			tagged Branch { op: .op }: begin
				let jump = case (op) matches
					tagged Equal: return cmp_result.eq;
					tagged NotEqual: return !cmp_result.eq;
					tagged LessThan: return cmp_result.lt;
					tagged GreaterThanOrEqual: return !cmp_result.lt;
					tagged LessThanUnsigned: return cmp_result.lt;
					tagged GreaterThanOrEqualUnsigned: return !cmp_result.lt;
				endcase;
				return tagged Ok ExecuteResultOk {
					x_regs_rd: 0,
					x_regs_rd_value: ?,
					csrd: tagged Invalid,
					jump_pc: jump ? tagged Valid add_result.add : tagged Invalid
				};
			end

			tagged Csr (tagged Csrr { rd: .rd, csrs: .csrs }): begin
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: csrs,
					csrd: tagged Invalid,
					jump_pc: tagged Valid add_result.add
				};
			end

			tagged Csr (tagged Csrs { rs1: .rs1, csrd: .csrd }): begin
				return tagged Ok ExecuteResultOk {
					x_regs_rd: 0,
					x_regs_rd_value: ?,
					csrd: tagged Valid tuple2(csrd, rs1),
					jump_pc: tagged Valid add_result.add
				};
			end

			tagged Csr (tagged Csrrw { rd: .rd, rs1: .rs1, csrd: .csrd, csrs: .csrs }): begin
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: csrs,
					csrd: tagged Valid tuple2(csrd, rs1),
					jump_pc: tagged Valid add_result.add
				};
			end

			tagged Csr (tagged Csrrs { rd: .rd, rs1: .rs1, csrd: .csrd, csrs: .csrs }): begin
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: csrs,
					csrd: tagged Valid tuple2(csrd, logical_result.or_),
					jump_pc: tagged Valid add_result.add
				};
			end

			tagged Csr (tagged Csrrc { rd: .rd, rs1: .rs1, csrd: .csrd, csrs: .csrs }): begin
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: csrs,
					csrd: tagged Valid tuple2(csrd, logical_result.and_),
					jump_pc: tagged Valid add_result.add
				};
			end

			tagged Jal { rd: .rd }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: next_pc,
					csrd: tagged Invalid,
					jump_pc: tagged Valid add_result.add
				};

			tagged Lui { rd: .rd, imm: .imm }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: extend(imm) << 12,
					csrd: tagged Invalid,
					jump_pc: tagged Invalid
				};

			tagged Unary { op: .op, rd: .rd, rs: .rs }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: case (op) matches
						tagged Clz: return popcnt_result.cpop;
						tagged Clzw: return popcnt_result.cpopw;
						tagged Cpop: return popcnt_result.cpop;
						tagged Cpopw: return popcnt_result.cpopw;
						tagged Ctz: return popcnt_result.cpop;
						tagged Ctzw: return popcnt_result.cpopw;
						tagged OrcB: return orc_b.run(rs);
						tagged Rev8: begin
							let rs_bits = pack(rs);
							return unpack({
								rs_bits[7:0],
								rs_bits[15:8],
								rs_bits[23:16],
								rs_bits[31:24],
								rs_bits[39:32],
								rs_bits[47:40],
								rs_bits[55:48],
								rs_bits[63:56]
							});
						end
						tagged SextB: begin
							Int#(8) rs_ = truncate(rs);
							return extend(rs_);
						end
						tagged SextH: begin
							Int#(16) rs_ = truncate(rs);
							return extend(rs_);
						end
						tagged ZextH: begin
							Int#(16) rs_ = truncate(rs);
							return zeroExtend(rs_);
						end
					endcase,
					csrd: tagged Invalid,
					jump_pc: tagged Invalid
				};

			default: return tagged Sigill;
		endcase
	endmethod
endmodule

interface Adder;
	method AddResult#(64) run(Int#(64) arg1, Int#(64) arg2, Bool cin);
endinterface

typedef struct {
	Int#(width) add;
	Int#(width) addw;
} AddResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkAdder(Adder);
	method AddResult#(64) run(Int#(64) arg1, Int#(64) arg2, Bool cin);
		let add = add_inner(arg1, arg2, cin);
		Int#(32) addw = truncate(add);
		return AddResult {
			add: add,
			addw: extend(addw)
		};
	endmethod
endmodule

function Int#(width) add_inner(Int#(width) arg1, Int#(width) arg2, Bool cin);
	let width = valueOf(width);

	return arg1 + arg2 + (cin ? 1 : 0);
endfunction

interface Cmp;
	method CmpResult cmp(Int#(64) arg1, Int#(64) arg2, Bool cmp_signed);
endinterface

typedef struct {
	Bool lt;
	Bool eq;
} CmpResult deriving(Bits);

(* synthesize *)
module mkCmp(Cmp);
	method CmpResult cmp(Int#(64) arg1, Int#(64) arg2, Bool cmp_signed);
		return cmp_inner(pack(arg1), pack(arg2), cmp_signed);
	endmethod
endmodule

typeclass CmpInner#(numeric type width);
	function CmpResult cmp_inner(Bit#(width) arg1, Bit#(width) arg2, Bool cmp_signed);
endtypeclass

instance CmpInner#(1);
	function CmpResult cmp_inner(Bit#(1) arg1, Bit#(1) arg2, Bool cmp_signed);
		let lt = ~((cmp_signed ? arg2[0] : arg1[0]) | ~(arg1[0] | arg2[0]));
		let eq = (arg1[0] & arg2[0]) | ~(arg1[0] | arg2[0]);
		return CmpResult { lt: unpack(pack(lt)), eq: unpack(pack(eq)) };
	endfunction
endinstance

instance CmpInner#(width)
provisos (
	Div#(width, 2, lo_width),
	Add#(lo_width, hi_width, width),
	CmpInner#(lo_width),
	CmpInner#(hi_width)
);
	function CmpResult cmp_inner(Bit#(width) arg1, Bit#(width) arg2, Bool cmp_signed);
		let width = valueOf(width);
		let lo_width = valueOf(lo_width);
		let hi_width = valueOf(hi_width);

		match { .arg1_hi, .arg1_lo } = split(arg1);
		match { .arg2_hi, .arg2_lo } = split(arg2);
		let lo = cmp_inner(Bit#(lo_width)'(arg1_lo), Bit#(lo_width)'(arg2_lo), False);
		let hi = cmp_inner(Bit#(hi_width)'(arg1_hi), Bit#(hi_width)'(arg2_hi), cmp_signed);

		let lt = hi.lt || (hi.eq && lo.lt);
		let eq = hi.eq && lo.eq;
		return CmpResult { lt: lt, eq: eq };
	endfunction
endinstance

interface Logical;
	method LogicalResult#(64) run(Int#(64) arg1, Int#(64) arg2, Bool invert_arg2);
endinterface

typedef struct {
	Int#(width) and_;
	Int#(width) or_;
	Int#(width) xor_;
} LogicalResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkLogical(Logical);
	method LogicalResult#(64) run(Int#(64) arg1, Int#(64) arg2, Bool invert_arg2);
		return logical_inner(arg1, arg2, invert_arg2);
	endmethod
endmodule

function LogicalResult#(width) logical_inner(Int#(width) arg1, Int#(width) arg2, Bool invert_arg2);
	let arg2_ = invert_arg2 ? ~arg2 : arg2;
	let and_ = arg1 & arg2_;
	let or_ = arg1 | arg2_;
	return LogicalResult {
		and_: and_,
		or_: or_,
		xor_: ~(and_ | ~or_)
	};
endfunction

interface OrcB;
	method Int#(64) run(Int#(64) arg);
endinterface

(* synthesize *)
module mkOrcB(OrcB);
	method Int#(64) run(Int#(64) arg);
		return unpack(orc_b_inner(pack(arg)));
	endmethod
endmodule

function Bit#(width) orc_b_inner(Bit#(width) arg)
provisos (
	Add#(a__, 8, width),
	Div#(width, 8, num_cells),
	Mul#(num_cells, 8, width)
);
	let num_cells = valueOf(num_cells);

	Bit#(width) result = 0;

	for (Integer i = 0; i < num_cells; i = i + 1) begin
		Bit#(8) cell_ = arg[i * 8 + 7:i * 8];
		cell_ = signExtend(| cell_);
		result[i * 8 + 7:i * 8] = cell_;
	end

	return result;
endfunction

interface Popcnt;
	method PopcntResult#(64) run(Int#(64) arg);
endinterface

typedef struct {
	Int#(width) cpop;
	Int#(width) cpopw;
} PopcntResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkPopcnt(Popcnt);
	method PopcntResult#(64) run(Int#(64) arg);
		Int#(64) cpopw = zeroExtend(unpack(pack(popcnt_inner(pack(arg)[31:0]))));
		let cpop = cpopw + zeroExtend(unpack(pack(popcnt_inner(pack(arg)[63:31]))));
		return PopcntResult {
			cpop: cpop,
			cpopw: cpopw
		};
	endmethod
endmodule

typeclass PopcntInner#(numeric type width);
	function UInt#(width) popcnt_inner(Bit#(width) arg);
endtypeclass

instance PopcntInner#(1);
	function UInt#(1) popcnt_inner(Bit#(1) arg);
		return unpack(arg);
	endfunction
endinstance

instance PopcntInner#(width)
provisos (
	Div#(width, 2, lo_width),
	Add#(lo_width, hi_width, width),
	PopcntInner#(lo_width),
	PopcntInner#(hi_width)
);
	function UInt#(width) popcnt_inner(Bit#(width) arg);
		let width = valueOf(width);
		let lo_width = valueOf(lo_width);
		let hi_width = valueOf(hi_width);

		Bit#(lo_width) arg_lo = arg[lo_width - 1:0];
		UInt#(width) lo = extend(popcnt_inner(arg_lo));

		Bit#(hi_width) arg_hi = arg[width - 1:lo_width];
		UInt#(width) hi = extend(popcnt_inner(arg_hi));

		return lo + hi;
	endfunction
endinstance

interface ShiftRotate;
	method Int#(64) run(Int#(64) value, Int#(64) shamt, Bool right, Bool rotate, Bool arithmetic, Bool w);
endinterface

(* synthesize *)
module mkShiftRotate(ShiftRotate);
	method Int#(64) run(Int#(64) value, Int#(64) shamt, Bool right, Bool rotate, Bool arithmetic, Bool w);
		Bit#(6) shamt_ = truncate(pack(shamt));
		return shift_rotate_inner(value, shamt_, right, rotate, arithmetic, w);
	endmethod
endmodule

function Int#(width) shift_rotate_inner(Int#(width) value, Bit#(shamt_width) shamt, Bool right, Bool rotate, Bool arithmetic, Bool w)
provisos (
	Add#(a__, 1, width),
	Add#(b__, 1, TDiv#(width, 2)),
	Add#(TDiv#(width, 2), TDiv#(width, 2), width),
	ShiftInnerRound#(width, TSub#(shamt_width, 1))
);
	let width = valueOf(width);
	let shamt_width = valueOf(shamt_width);

	Bit#(width) value_ = pack(value);
	if (w) begin
		Bit#(TDiv#(width, 2)) value_lo = truncate(value_);
		value_ = { value_lo, value_lo };
	end

	if (!right)
		shamt = ~shamt;

	Bit#(width) r = right ? value_ : rotateBitsBy(value_, fromInteger(width - 1));

	Bit#(width) p = signExtend(pack(right || rotate));
	p[width - 1] = 1;

	Bit#(width) result = 0;

	Tuple2#(Bit#(1), Bit#(TSub#(shamt_width, 1))) shamt_parts = split(shamt);
	match { .shamt_hi, .shamt_lo } = shamt_parts;

	let round_result = shift_rotate_inner_round(shamt_lo, right, rotate, 0, r, p);
	r = round_result.r;
	p = round_result.p;

	if (w) begin
		Bit#(TDiv#(width, 2)) r_lo = truncate(r);
		Bit#(TDiv#(width, 2)) p_hi = truncateLSB(p);

		let result_lo = (r_lo & p_hi) | ~((signExtend(arithmetic ? 0 : value_[width - 1])) | p_hi);
		result = signExtend(result_lo);

	end else begin
		let round_result = shift_rotate_inner_round(shamt_hi, right, rotate, shamt_width - 1, r, p);
		r = round_result.r;
		p = round_result.p;

		result = (r & p) | ~(signExtend(arithmetic ? 0 : value_[width - 1]) | p);
	end

	return unpack(result);
endfunction

typeclass ShiftInnerRound#(numeric type width, numeric type shamt_width);
	function ShiftInnerRoundResult#(width) shift_rotate_inner_round(
		Bit#(shamt_width) shamt,
		Bool right,
		Bool rotate,
		Integer i,
		Bit#(width) r,
		Bit#(width) p
	);
endtypeclass

instance ShiftInnerRound#(width, 0);
	function ShiftInnerRoundResult#(width) shift_rotate_inner_round(
		Bit#(0) shamt,
		Bool right,
		Bool rotate,
		Integer i,
		Bit#(width) r,
		Bit#(width) p
	);
		return ShiftInnerRoundResult { r: r, p: p };
	endfunction
endinstance

instance ShiftInnerRound#(width, shamt_width)
provisos (
	Add#(a__, 1, width),
	ShiftInnerRound#(width, TSub#(shamt_width, 1))
);
	function ShiftInnerRoundResult#(width) shift_rotate_inner_round(
		Bit#(shamt_width) shamt,
		Bool right,
		Bool rotate,
		Integer i,
		Bit#(width) r,
		Bit#(width) p
	);
		let width = valueOf(width);

		if (unpack(shamt[0])) begin
			let r_ = r;
			r = (r_ >> (2 ** i)) | (r_ << (width - 2 ** i));

			let p_ = p;
			Bit#(width) p__ = signExtend(pack(!right || rotate));
			p = (p_ >> (2 ** i)) | (p__ << (width - 2 ** i));
		end

		Bit#(TSub#(shamt_width, 1)) shamt_ = truncateLSB(shamt);
		return shift_rotate_inner_round(shamt_, right, rotate, i + 1, r, p);
	endfunction
endinstance

typedef struct {
	Bit#(width) r;
	Bit#(width) p;
} ShiftInnerRoundResult#(numeric type width) deriving(Bits);
