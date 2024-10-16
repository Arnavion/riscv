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
	Shift shift <- mkShift;

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

			default: return ?;
		endcase;
		let add_result = adder.run(adder_a, adder_b, adder_cin);

		match { .cmp_a, .cmp_b, .cmp_signed } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
					tagged CzeroEqz: return tuple3(0, rs2, ?);
					tagged CzeroNez: return tuple3(0, rs2, ?);
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

		match { .logical_arg1, .logical_arg2 } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }: begin
				UInt#(64) rs2u = unpack(pack(rs2));
				UInt#(6) rs2_shamt = truncate(rs2u);
				Int#(64) rs2_decoded = 1 << rs2_shamt;

				case (op) matches
					tagged And: return tuple2(rs1, rs2);
					tagged Bclr: return tuple2(rs1, ~rs2_decoded);
					tagged Binv: return tuple2(rs1, rs2_decoded);
					tagged Bset: return tuple2(rs1, rs2_decoded);
					tagged Or: return tuple2(rs1, rs2);
					tagged Xor: return tuple2(rs1, rs2);
					default: return ?;
				endcase
			end

			tagged Csr .op:
				case (op) matches
					tagged Csrrs { rs1: .rs1, csrs: .csrs }: return tuple2(csrs, rs1);
					tagged Csrrc { rs1: .rs1, csrs: .csrs }: return tuple2(csrs, ~rs1);
					default: return ?;
				endcase

			default: return ?;
		endcase;
		let logical_result = logical.run(logical_arg1, logical_arg2);

		match { .shift_value, .shift_shamt, .shift_arithmetic } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }: begin
				Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));

				case (op) matches
					tagged Bext: return tuple3(rs1, rs2, ?);
					tagged Sll: return tuple3(rs1, rs2, ?);
					tagged SllUw: return tuple3(rs1uw, rs2, ?);
					tagged Sllw: return tuple3(rs1, rs2, ?);
					tagged Sra: return tuple3(rs1, rs2, True);
					tagged Sraw: return tuple3(rs1, rs2, True);
					tagged Srl: return tuple3(rs1, rs2, False);
					tagged Srlw: return tuple3(rs1, rs2, False);
					default: return ?;
				endcase
			end

			default: return ?;
		endcase;
		let shift_result = shift.run(shift_value, shift_shamt, shift_arithmetic);

		case (inst) matches
			tagged Auipc { rd: .rd }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: add_result.add,
					csrd: tagged Invalid,
					jump_pc: tagged Invalid
				};

			tagged Binary { op: .op, rd: .rd, rs1: .rs1 }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: case (op) matches
						tagged Add: return add_result.add;
						tagged AddUw: return add_result.add;
						tagged Addw: return add_result.addw;
						tagged And: return logical_result.and_;
						tagged Bclr: return logical_result.and_;
						tagged Bext: return shift_result.sr & 1;
						tagged Binv: return logical_result.xor_;
						tagged Bset: return logical_result.or_;
						tagged CzeroEqz: return cmp_result.eq ? 0 : rs1;
						tagged CzeroNez: return cmp_result.eq ? rs1 : 0;
						tagged Or: return logical_result.or_;
						tagged Sh1add: return add_result.add;
						tagged Sh1addUw: return add_result.add;
						tagged Sh2add: return add_result.add;
						tagged Sh2addUw: return add_result.add;
						tagged Sh3add: return add_result.add;
						tagged Sh3addUw: return add_result.add;
						tagged Sll: return shift_result.sll;
						tagged SllUw: return shift_result.sll;
						tagged Sllw: return shift_result.sll;
						tagged Slt: return cmp_result.lt ? 1 : 0;
						tagged Sltu: return cmp_result.lt ? 1 : 0;
						tagged Sra: return shift_result.sr;
						tagged Sraw: return shift_result.sr;
						tagged Srl: return shift_result.sr;
						tagged Srlw: return shift_result.sr;
						tagged Sub: return add_result.add;
						tagged Subw: return add_result.addw;
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
	method LogicalResult#(64) run(Int#(64) arg1, Int#(64) arg2);
endinterface

typedef struct {
	Int#(width) and_;
	Int#(width) or_;
	Int#(width) xor_;
} LogicalResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkLogical(Logical);
	method LogicalResult#(64) run(Int#(64) arg1, Int#(64) arg2);
		return logical_inner(arg1, arg2);
	endmethod
endmodule

function LogicalResult#(width) logical_inner(Int#(width) arg1, Int#(width) arg2);
	let and_ = arg1 & arg2;
	let or_ = arg1 | arg2;
	return LogicalResult {
		and_: and_,
		or_: or_,
		xor_: ~(and_ | ~or_)
	};
endfunction

interface Shift;
	method ShiftResult#(64) run(Int#(64) value, Int#(64) shamt, Bool arithmetic);
endinterface

typedef struct {
	Int#(width) sll;
	Int#(width) sllw;
	Int#(width) sr;
	Int#(width) srw;
} ShiftResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkShift(Shift);
	method ShiftResult#(64) run(Int#(64) value, Int#(64) shamt, Bool arithmetic);
		Bit#(5) shamt32 = truncate(pack(shamt));
		Int#(32) sll_value32 = truncate(value);
		Bit#(33) sr_value32 = arithmetic ? signExtend(pack(sll_value32)) : zeroExtend(pack(sll_value32));
		let shift_inner_result32 = shift_inner(sll_value32, unpack(sr_value32), shamt32, 16);

		Bit#(6) shamt64 = truncate(pack(shamt));
		Bit#(65) sr_value64 = arithmetic ? signExtend(pack(value)) : zeroExtend(pack(value));
		let shift_inner_result64 = shift_inner(value, unpack(sr_value64), shamt64, 32);

		return ShiftResult {
			sll: shift_inner_result64.sll,
			sllw: signExtend(shift_inner_result32.sll),
			sr: shift_inner_result64.sr,
			srw: signExtend(shift_inner_result32.sr)
		};
	endmethod
endmodule

typeclass Shifter#(numeric type width, numeric type shamt_width);
	function ShiftInnerResult#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(shamt_width) shamt, Integer offset);
endtypeclass

typedef struct {
	Int#(width) sll;
	Int#(width) sr;
} ShiftInnerResult#(numeric type width) deriving(Bits);

instance Shifter#(width, 0);
	function ShiftInnerResult#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(0) shamt, Integer offset);
		return ShiftInnerResult {
			sll: sll,
			sr: unpack(truncate(pack(sr)))
		};
	endfunction
endinstance

instance Shifter#(width, shamt_width)
provisos (
	Shifter#(width, TSub#(shamt_width, 1))
);
	function ShiftInnerResult#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(shamt_width) shamt, Integer offset);
		if (shamt[valueOf(TSub#(shamt_width, 1))] != 0) begin
			sll = sll << offset;
			sr = sr >> offset;
		end
		Bit#(TSub#(shamt_width, 1)) shamt_ = truncate(shamt);
		return shift_inner(sll, sr, shamt_, offset / 2);
	endfunction
endinstance
