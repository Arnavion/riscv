import ClientServer::*;
import GetPut::*;

import RvCommon::*;

typedef Server#(AluRequest, AluResponse) RvAlu;

typedef struct {
	Int#(64) pc;
	Int#(64) next_pc;
	Instruction#(Int#(64), Int#(64)) inst;
} AluRequest deriving(Bits);

typedef union tagged {
	void Efault;
	void Sigill;
	AluResponseOk Ok;
} AluResponse deriving(Bits);

typedef struct {
	XReg x_regs_rd;
	Int#(64) x_regs_rd_value;
	Int#(64) next_pc;
} AluResponseOk deriving(Bits);

(* synthesize *)
module mkRvAlu(RvAlu);
	Adder adder <- mkAdder;
	Cmp cmp <- mkCmp;
	Logical logical <- mkLogical;
	Shift shift <- mkShift;

	Wire#(Int#(64)) pc <- mkWire;
	Wire#(Int#(64)) next_pc <- mkWire;
	Wire#(Instruction#(Int#(64), Int#(64))) inst <- mkWire;

	RWire#(AluResponse) result <- mkRWire;

	// add
	rule add_1(inst matches tagged Binary { op: Add, rs1: .rs1, rs2: .rs2 });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule add_end(inst matches tagged Binary { op: Add, rd: .rd });
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			next_pc: next_pc
		});
	endrule

	// addw
	rule addw_1(inst matches tagged Binary { op: Addw, rs1: .rs1, rs2: .rs2 });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule addw_end(inst matches tagged Binary { op: Addw, rd: .rd });
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.addw,
			next_pc: next_pc
		});
	endrule

	// and
	rule and_1(inst matches tagged Binary { op: And, rs1: .rs1, rs2: .rs2 });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2
		});
	endrule

	rule and_end(inst matches tagged Binary { op: And, rd: .rd });
		let logical_response <- logical.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.and_,
			next_pc: next_pc
		});
	endrule

	// auipc
	rule auipc_1(inst matches tagged Auipc { imm: .imm });
		adder.request.put(AdderRequest {
			arg1: pc,
			arg2: extend(imm),
			cin: False
		});
	endrule

	rule auipc_end(inst matches tagged Auipc { rd: .rd });
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			next_pc: next_pc
		});
	endrule

	// branch
	rule branch_1(inst matches tagged Branch { imm: .imm });
		adder.request.put(AdderRequest {
			arg1: pc,
			arg2: extend(imm),
			cin: False
		});
	endrule

	rule branch_2(inst matches tagged Branch { op: .op, rs1: .rs1, rs2: .rs2 });
		case (op) matches
			tagged Equal: begin
				cmp.request.put(CmpRequest {
					arg1: rs1,
					arg2: rs2,
					signed_: ?
				});
			end
			tagged NotEqual: begin
				cmp.request.put(CmpRequest {
					arg1: rs1,
					arg2: rs2,
					signed_: ?
				});
			end
			tagged LessThan: begin
				cmp.request.put(CmpRequest {
					arg1: rs1,
					arg2: rs2,
					signed_: True
				});
			end
			tagged GreaterThanOrEqual: begin
				cmp.request.put(CmpRequest {
					arg1: rs1,
					arg2: rs2,
					signed_: True
				});
			end
			tagged LessThanUnsigned: begin
				cmp.request.put(CmpRequest {
					arg1: rs1,
					arg2: rs2,
					signed_: False
				});
			end
			tagged GreaterThanOrEqualUnsigned: begin
				cmp.request.put(CmpRequest {
					arg1: rs1,
					arg2: rs2,
					signed_: False
				});
			end
		endcase
	endrule

	rule branch_end(inst matches tagged Branch { op: .op });
		let cmp_response <- cmp.response.get;
		let jump = case (op) matches
			tagged Equal: return cmp_response.eq;
			tagged NotEqual: return !cmp_response.eq;
			tagged LessThan: return cmp_response.lt;
			tagged GreaterThanOrEqual: return !cmp_response.lt;
			tagged LessThanUnsigned: return cmp_response.lt;
			tagged GreaterThanOrEqualUnsigned: return !cmp_response.lt;
		endcase;
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: 0,
			x_regs_rd_value: ?,
			next_pc: jump ? adder_response.add : next_pc
		});
	endrule

	// jal, jalr
	rule jal_1(inst matches tagged Jal { base: tagged Pc, offset: .offset });
		adder.request.put(AdderRequest {
			arg1: pc,
			arg2: extend(offset),
			cin: False
		});
	endrule

	rule jal_2(inst matches tagged Jal { base: tagged XReg .base, offset: .offset });
		adder.request.put(AdderRequest {
			arg1: base,
			arg2: extend(offset),
			cin: False
		});
	endrule

	rule jal_end(inst matches tagged Jal { rd: .rd });
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: next_pc,
			next_pc: adder_response.add
		});
	endrule

	// lui
	rule li_end(inst matches tagged Li { rd: .rd, imm: .imm });
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: extend(imm),
			next_pc: next_pc
		});
	endrule

	// or
	rule or_1(inst matches tagged Binary { op: Or, rs1: .rs1, rs2: .rs2 });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2
		});
	endrule

	rule or_end(inst matches tagged Binary { op: Or, rd: .rd });
		let logical_response <- logical.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.or_,
			next_pc: next_pc
		});
	endrule

	// sll
	rule sll_1(inst matches tagged Binary { op: Sll, rs1: .rs1, rs2: .rs2 });
		shift.request.put(ShiftRequest {
			value: rs1,
			shamt: rs2,
			arithmetic: ?
		});
	endrule

	rule sll_end(inst matches tagged Binary { op: Sll, rd: .rd });
		let shift_response <- shift.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_response.sll,
			next_pc: next_pc
		});
	endrule

	// sllw
	rule sllw_1(inst matches tagged Binary { op: Sllw, rs1: .rs1, rs2: .rs2 });
		shift.request.put(ShiftRequest {
			value: rs1,
			shamt: rs2,
			arithmetic: ?
		});
	endrule

	rule sllw_end(inst matches tagged Binary { op: Sllw, rd: .rd });
		let shift_response <- shift.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_response.sllw,
			next_pc: next_pc
		});
	endrule

	// sra
	rule sra_1(inst matches tagged Binary { op: Sra, rs1: .rs1, rs2: .rs2 });
		shift.request.put(ShiftRequest {
			value: rs1,
			shamt: rs2,
			arithmetic: True
		});
	endrule

	rule sra_end(inst matches tagged Binary { op: Sra, rd: .rd });
		let shift_response <- shift.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_response.sr,
			next_pc: next_pc
		});
	endrule

	// sraw
	rule sraw_1(inst matches tagged Binary { op: Sraw, rs1: .rs1, rs2: .rs2 });
		shift.request.put(ShiftRequest {
			value: rs1,
			shamt: rs2,
			arithmetic: True
		});
	endrule

	rule sraw_end(inst matches tagged Binary { op: Sraw, rd: .rd });
		let shift_response <- shift.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_response.srw,
			next_pc: next_pc
		});
	endrule

	// srl
	rule srl_1(inst matches tagged Binary { op: Srl, rs1: .rs1, rs2: .rs2 });
		shift.request.put(ShiftRequest {
			value: rs1,
			shamt: rs2,
			arithmetic: False
		});
	endrule

	rule srl_end(inst matches tagged Binary { op: Srl, rd: .rd });
		let shift_response <- shift.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_response.sr,
			next_pc: next_pc
		});
	endrule

	// srlw
	rule srlw_1(inst matches tagged Binary { op: Srlw, rs1: .rs1, rs2: .rs2 });
		shift.request.put(ShiftRequest {
			value: rs1,
			shamt: rs2,
			arithmetic: False
		});
	endrule

	rule srlw_end(inst matches tagged Binary { op: Srlw, rd: .rd });
		let shift_response <- shift.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_response.srw,
			next_pc: next_pc
		});
	endrule

	// slt
	rule slt_1(inst matches tagged Binary { op: Slt, rs1: .rs1, rs2: .rs2 });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: True
		});
	endrule

	rule slt_end(inst matches tagged Binary { op: Slt, rd: .rd });
		let cmp_response <- cmp.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? 1 : 0,
			next_pc: next_pc
		});
	endrule

	// sltu
	rule sltu_1(inst matches tagged Binary { op: Sltu, rs1: .rs1, rs2: .rs2 });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: False
		});
	endrule

	rule sltu_end(inst matches tagged Binary { op: Sltu, rd: .rd });
		let cmp_response <- cmp.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? 1 : 0,
			next_pc: next_pc
		});
	endrule

	// sub
	rule sub_1(inst matches tagged Binary { op: Sub, rs1: .rs1, rs2: .rs2 });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: ~rs2,
			cin: True
		});
	endrule

	rule sub_end(inst matches tagged Binary { op: Sub, rd: .rd });
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			next_pc: next_pc
		});
	endrule

	// subw
	rule subw_1(inst matches tagged Binary { op: Subw, rs1: .rs1, rs2: .rs2 });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: ~rs2,
			cin: True
		});
	endrule

	rule subw_end(inst matches tagged Binary { op: Subw, rd: .rd });
		let adder_response <- adder.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.addw,
			next_pc: next_pc
		});
	endrule

	// xor
	rule xor_1(inst matches tagged Binary { op: Xor, rs1: .rs1, rs2: .rs2 });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2
		});
	endrule

	rule xor_end(inst matches tagged Binary { op: Xor, rd: .rd });
		let logical_response <- logical.response.get;
		result.wset(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.xor_,
			next_pc: next_pc
		});
	endrule

	interface Put request;
		method Action put(AluRequest request);
			pc <= request.pc;
			next_pc <= request.next_pc;
			inst <= request.inst;
		endmethod
	endinterface

	interface response = toGet(result);
endmodule

typedef Server#(AdderRequest#(64), AdderResponse#(64)) Adder;

typedef struct {
	Int#(width) arg1;
	Int#(width) arg2;
	Bool cin;
} AdderRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) add;
	Int#(width) addw;
} AdderResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkAdder(Adder);
	Wire #(Int#(64)) arg1 <- mkWire;
	Wire #(Int#(64)) arg2 <- mkWire;
	Wire #(Bool) cin <- mkWire;
	RWire#(AdderResponse#(64)) result <- mkRWire;

	rule run;
		let add = add_inner(arg1, arg2, cin);
		Int#(32) addw = truncate(add);
		result.wset(AdderResponse {
			add: add,
			addw: extend(addw)
		});
	endrule

	interface Put request;
		method Action put(AdderRequest#(64) request);
			arg1 <= request.arg1;
			arg2 <= request.arg2;
			cin <= request.cin;
		endmethod
	endinterface

	interface response = toGet(result);
endmodule

function Int#(width) add_inner(Int#(width) arg1, Int#(width) arg2, Bool cin);
	let width = valueOf(width);

	return arg1 + arg2 + (cin ? 1 : 0);
endfunction

typedef Server#(CmpRequest#(64), CmpResponse) Cmp;

typedef struct {
	Int#(width) arg1;
	Int#(width) arg2;
	Bool signed_;
} CmpRequest#(numeric type width) deriving(Bits);

typedef struct {
	Bool lt;
	Bool eq;
} CmpResponse deriving(Bits);

(* synthesize *)
module mkCmp(Cmp);
	Wire#(Int#(64)) arg1 <- mkWire;
	Wire#(Int#(64)) arg2 <- mkWire;
	Wire#(Bool) signed_ <- mkWire;
	RWire#(CmpResponse) result <- mkRWire;

	rule run;
		result.wset(cmp_inner(pack(arg1), pack(arg2), signed_));
	endrule

	interface Put request;
		method Action put(CmpRequest#(64) request);
			arg1 <= request.arg1;
			arg2 <= request.arg2;
			signed_ <= request.signed_;
		endmethod
	endinterface

	interface response = toGet(result);
endmodule

typeclass CmpInner#(numeric type width);
	function CmpResponse cmp_inner(Bit#(width) arg1, Bit#(width) arg2, Bool signed_);
endtypeclass

instance CmpInner#(1);
	function CmpResponse cmp_inner(Bit#(1) arg1, Bit#(1) arg2, Bool signed_);
		let lt = ~((signed_ ? arg2[0] : arg1[0]) | ~(arg1[0] | arg2[0]));
		let eq = (arg1[0] & arg2[0]) | ~(arg1[0] | arg2[0]);
		return CmpResponse { lt: unpack(pack(lt)), eq: unpack(pack(eq)) };
	endfunction
endinstance

instance CmpInner#(width)
provisos (
	Div#(width, 2, lo_width),
	Add#(lo_width, hi_width, width),
	CmpInner#(lo_width),
	CmpInner#(hi_width)
);
	function CmpResponse cmp_inner(Bit#(width) arg1, Bit#(width) arg2, Bool signed_);
		let width = valueOf(width);
		let lo_width = valueOf(lo_width);
		let hi_width = valueOf(hi_width);

		match { .arg1_hi, .arg1_lo } = split(arg1);
		match { .arg2_hi, .arg2_lo } = split(arg2);
		let lo = cmp_inner(Bit#(lo_width)'(arg1_lo), Bit#(lo_width)'(arg2_lo), False);
		let hi = cmp_inner(Bit#(hi_width)'(arg1_hi), Bit#(hi_width)'(arg2_hi), signed_);

		let lt = hi.lt || (hi.eq && lo.lt);
		let eq = hi.eq && lo.eq;
		return CmpResponse { lt: lt, eq: eq };
	endfunction
endinstance

typedef Server#(LogicalRequest#(64), LogicalResponse#(64)) Logical;

typedef struct {
	Int#(width) arg1;
	Int#(width) arg2;
} LogicalRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) and_;
	Int#(width) or_;
	Int#(width) xor_;
} LogicalResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkLogical(Logical);
	Wire#(Int#(64)) arg1 <- mkWire;
	Wire#(Int#(64)) arg2 <- mkWire;
	RWire#(LogicalResponse#(64)) result <- mkRWire;

	rule run;
		result.wset(logical_inner(arg1, arg2));
	endrule

	interface Put request;
		method Action put(LogicalRequest#(64) request);
			arg1 <= request.arg1;
			arg2 <= request.arg2;
		endmethod
	endinterface

	interface response = toGet(result);
endmodule

function LogicalResponse#(width) logical_inner(Int#(width) arg1, Int#(width) arg2);
	let and_ = arg1 & arg2;
	let or_ = arg1 | arg2;
	return LogicalResponse {
		and_: and_,
		or_: or_,
		xor_: ~(and_ | ~or_)
	};
endfunction

typedef Server#(ShiftRequest#(64), ShiftResponse#(64)) Shift;

typedef struct {
	Int#(width) value;
	Int#(width) shamt;
	Bool arithmetic;
} ShiftRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) sll;
	Int#(width) sllw;
	Int#(width) sr;
	Int#(width) srw;
} ShiftResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkShift(Shift);
	Wire#(Int#(64)) value <- mkWire;
	Wire#(Int#(64)) shamt <- mkWire;
	Wire#(Bool) arithmetic <- mkWire;
	RWire#(ShiftResponse#(64)) result <- mkRWire;

	rule run;
		Bit#(5) shamt32 = truncate(pack(shamt));
		Int#(32) sll_value32 = truncate(value);
		Bit#(33) sr_value32 = arithmetic ? signExtend(pack(sll_value32)) : zeroExtend(pack(sll_value32));
		let shift_inner_result32 = shift_inner(sll_value32, unpack(sr_value32), shamt32, 16);

		Bit#(6) shamt64 = truncate(pack(shamt));
		Bit#(65) sr_value64 = arithmetic ? signExtend(pack(value)) : zeroExtend(pack(value));
		let shift_inner_result64 = shift_inner(value, unpack(sr_value64), shamt64, 32);

		result.wset(ShiftResponse {
			sll: shift_inner_result64.sll,
			sllw: signExtend(shift_inner_result32.sll),
			sr: shift_inner_result64.sr,
			srw: signExtend(shift_inner_result32.sr)
		});
	endrule

	interface Put request;
		method Action put(ShiftRequest#(64) request);
			value <= request.value;
			shamt <= request.shamt;
			arithmetic <= request.arithmetic;
		endmethod
	endinterface

	interface response = toGet(result);
endmodule

typeclass Shifter#(numeric type width, numeric type shamt_width);
	function ShiftInnerResponse#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(shamt_width) shamt, Integer offset);
endtypeclass

typedef struct {
	Int#(width) sll;
	Int#(width) sr;
} ShiftInnerResponse#(numeric type width) deriving(Bits);

instance Shifter#(width, 0);
	function ShiftInnerResponse#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(0) shamt, Integer offset);
		return ShiftInnerResponse {
			sll: sll,
			sr: unpack(truncate(pack(sr)))
		};
	endfunction
endinstance

instance Shifter#(width, shamt_width)
provisos (
	Shifter#(width, TSub#(shamt_width, 1))
);
	function ShiftInnerResponse#(width) shift_inner(Int#(width) sll, Int#(TAdd#(width, 1)) sr, Bit#(shamt_width) shamt, Integer offset);
		if (shamt[valueOf(TSub#(shamt_width, 1))] != 0) begin
			sll = sll << offset;
			sr = sr >> offset;
		end
		Bit#(TSub#(shamt_width, 1)) shamt_ = truncate(shamt);
		return shift_inner(sll, sr, shamt_, offset / 2);
	endfunction
endinstance
