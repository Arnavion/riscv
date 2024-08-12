import Vector::*;

import RvCommon::*;
import RvDecoder::*;

interface RvAlu;
	method ExecuteResult execute(
		Int#(32) pc,
		Int#(32) next_pc,
		Instruction#(Int#(32)) inst
	);
endinterface

typedef union tagged {
	void Efault;
	void Sigill;
	ExecuteResultOk Ok;
} ExecuteResult deriving(Bits);

typedef struct {
	XReg x_regs_rd;
	Int#(32) x_regs_rd_value;
	Maybe#(Int#(32)) jump_pc;
} ExecuteResultOk deriving(Bits);

(* synthesize *)
module mkRvAlu(RvAlu);
	Adder adder <- mkAdder;
	Cmp cmp <- mkCmp;
	Logical logical <- mkLogical;
	Shift shift <- mkShift;

	method ExecuteResult execute(
		Int#(32) pc,
		Int#(32) next_pc,
		Instruction#(Int#(32)) inst
	);
		match { .adder_a, .adder_b, .adder_cin } = case (inst) matches
			tagged Auipc { imm: .imm }:
				return tuple3(pc, extend(imm) << 12, False);

			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
					tagged Add: return tuple3(rs1, rs2, False);
					tagged Sub: return tuple3(rs1, ~rs2, True);
					default: return ?;
				endcase

			tagged Branch { imm: .imm }:
				return tuple3(pc, extend(imm) << 1, False);

			tagged Jal { op: tagged Pc { offset: .offset } }:
				return tuple3(pc, extend(offset) << 1, False);

			tagged Jal { op: tagged XReg { base: .base, offset: .offset } }:
				return tuple3(base, extend(offset), False);

			default: return ?;
		endcase;
		let add_result = adder.add(adder_a, adder_b, adder_cin);

		match { .cmp_a, .cmp_b, .cmp_signed } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
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
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
					tagged And: return tuple2(rs1, rs2);
					tagged Or: return tuple2(rs1, rs2);
					tagged Xor: return tuple2(rs1, rs2);
					default: return ?;
				endcase

			default: return ?;
		endcase;
		let logical_result = logical.run(logical_arg1, logical_arg2);

		match { .shift_value, .shift_shamt, .shift_arithmetic } = case (inst) matches
			tagged Binary { op: .op, rs1: .rs1, rs2: .rs2 }:
				case (op) matches
					tagged Sll: return tuple3(rs1, rs2, ?);
					tagged Sra: return tuple3(rs1, rs2, True);
					tagged Srl: return tuple3(rs1, rs2, False);
					default: return ?;
				endcase

			default: return ?;
		endcase;
		let shift_result = shift.run(shift_value, shift_shamt, shift_arithmetic);

		case (inst) matches
			tagged Auipc { rd: .rd }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: add_result,
					jump_pc: tagged Invalid
				};

			tagged Binary { op: .op, rd: .rd }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: case (op) matches
						tagged Add: return add_result;
						tagged And: return logical_result.and_;
						tagged Or: return logical_result.or_;
						tagged Sll: return shift_result.sll;
						tagged Slt: return cmp_result.lt ? 1 : 0;
						tagged Sltu: return cmp_result.lt ? 1 : 0;
						tagged Sra: return shift_result.sr;
						tagged Srl: return shift_result.sr;
						tagged Sub: return add_result;
						tagged Xor: return logical_result.xor_;
					endcase,
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
					jump_pc: jump ? tagged Valid add_result : tagged Invalid
				};
			end

			tagged Jal { rd: .rd }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: next_pc,
					jump_pc: tagged Valid add_result
				};

			tagged Lui { rd: .rd, imm: .imm }:
				return tagged Ok ExecuteResultOk {
					x_regs_rd: rd,
					x_regs_rd_value: extend(imm) << 12,
					jump_pc: tagged Invalid
				};

			default: return tagged Sigill;
		endcase
	endmethod
endmodule

interface Adder;
	method Int#(32) add(Int#(32) arg1, Int#(32) arg2, Bool cin);
endinterface

(* synthesize *)
module mkAdder(Adder);
	method Int#(32) add(Int#(32) arg1, Int#(32) arg2, Bool cin);
		return add_inner(arg1, arg2, cin);
	endmethod
endmodule

function Int#(width) add_inner(Int#(width) arg1, Int#(width) arg2, Bool cin);
	let width = valueOf(width);

	return arg1 + arg2 + (cin ? 1 : 0);
endfunction

interface Cmp;
	method CmpResult cmp(Int#(32) arg1, Int#(32) arg2, Bool cmp_signed);
endinterface

typedef struct {
	Bool lt;
	Bool eq;
} CmpResult deriving(Bits);

(* synthesize *)
module mkCmp(Cmp);
	method CmpResult cmp(Int#(32) arg1, Int#(32) arg2, Bool cmp_signed);
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
	method LogicalResult#(32) run(Int#(32) arg1, Int#(32) arg2);
endinterface

typedef struct {
	Int#(width) and_;
	Int#(width) or_;
	Int#(width) xor_;
} LogicalResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkLogical(Logical);
	method LogicalResult#(32) run(Int#(32) arg1, Int#(32) arg2);
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
	method ShiftResult#(32) run(Int#(32) value, Int#(32) shamt, Bool arithmetic);
endinterface

typedef struct {
	Int#(width) sll;
	Int#(width) sr;
} ShiftResult#(numeric type width) deriving(Bits);

(* synthesize *)
module mkShift(Shift);
	method ShiftResult#(32) run(Int#(32) value, Int#(32) shamt, Bool arithmetic);
		Bit#(5) shamt_ = truncate(pack(shamt));
		Bit#(33) value_ = arithmetic ? signExtend(pack(value)) : zeroExtend(pack(value));
		return shift_inner(value, unpack(value_), shamt_, 16);
	endmethod
endmodule

typeclass Shifter#(numeric type width, numeric type shamt_width);
	function ShiftResult#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(shamt_width) shamt, Integer offset);
endtypeclass

instance Shifter#(width, 0);
	function ShiftResult#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(0) shamt, Integer offset);
		return ShiftResult {
			sll: sll,
			sr: unpack(truncate(pack(sr)))
		};
	endfunction
endinstance

instance Shifter#(width, shamt_width)
provisos (
	Shifter#(width, TSub#(shamt_width, 1))
);
	function ShiftResult#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(shamt_width) shamt, Integer offset);
		if (shamt[valueOf(TSub#(shamt_width, 1))] != 0) begin
			sll = sll << offset;
			sr = sr >> offset;
		end
		Bit#(TSub#(shamt_width, 1)) shamt_ = truncate(shamt);
		return shift_inner(sll, sr, shamt_, offset / 2);
	endfunction
endinstance
