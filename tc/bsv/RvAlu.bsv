import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;
import Vector::*;

import Common::*;
import RvCommon::*;

typedef Server#(AluRequest, AluResponse) RvAlu;

typedef struct {
	Int#(64) pc;
	Int#(64) next_pc;
	Instruction#(Int#(64), Int#(64), Int#(64)) inst;
} AluRequest deriving(Bits);

typedef union tagged {
	void Efault;
	void Sigill;
	AluResponseOk Ok;
} AluResponse deriving(Bits);

typedef struct {
	XReg x_regs_rd;
	Int#(64) x_regs_rd_value;
	Maybe#(Tuple2#(Csr, Int#(64))) csrd;
	Int#(64) next_pc;
} AluResponseOk deriving(Bits);

(* synthesize *)
module mkRvAlu(RvAlu);
	Adder#(64) adder <- mkAdder;
	Cmp#(64) cmp <- mkCmp;
	Logical#(64) logical <- mkLogical;
	Multiplier#(64) multiplier <- mkMultiplier;
	OrcB#(64) orc_b <- mkOrcB;
	Popcnt#(64) popcnt <- mkPopcnt;
	ShiftRotate#(64) shift_rotate <- mkShiftRotate;

	FIFO#(AluRequest) args_ <- mkBypassFIFO;
	GetS#(AluRequest) args = fifoToGetS(args_);
	FIFO#(AluResponse) result_ <- mkBypassFIFO;
	Put#(AluResponse) result = toPut(result_);

	// add
	rule add_1(args.first matches AluRequest { inst: tagged Binary { op: Add, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule add_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Add, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// add.uw
	rule add_uw_1(args.first matches AluRequest { inst: tagged Binary { op: AddUw, rs1: .rs1, rs2: .rs2 } });
		Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));
		adder.request.put(AdderRequest {
			arg1: rs1uw,
			arg2: rs2,
			cin: False
		});
	endrule

	rule add_uw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: AddUw, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// addw
	rule addw_1(args.first matches AluRequest { inst: tagged Binary { op: Addw, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule addw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Addw, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.addw,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// and
	rule and_1(args.first matches AluRequest { inst: tagged Binary { op: And, rs1: .rs1, rs2: .rs2 } });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2,
			invert_arg2: False
		});
	endrule

	rule and_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: And, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.and_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// andn
	rule andn_1(args.first matches AluRequest { inst: tagged Binary { op: Andn, rs1: .rs1, rs2: .rs2 } });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2,
			invert_arg2: True
		});
	endrule

	rule andn_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Andn, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.and_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// auipc
	rule auipc_1(args.first matches AluRequest { pc: .pc, inst: tagged Auipc { imm: .imm } });
		adder.request.put(AdderRequest {
			arg1: pc,
			arg2: extend(imm),
			cin: False
		});
	endrule

	rule auipc_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Auipc { rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// bclr
	rule bclr_1(args.first matches AluRequest { inst: tagged Binary { op: Bclr, rs1: .rs1, rs2: .rs2 } });
		UInt#(64) rs2u = unpack(pack(rs2));
		UInt#(6) rs2_shamt = truncate(rs2u);
		Int#(64) rs2_decoded = 1 << rs2_shamt;
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2_decoded,
			invert_arg2: True
		});
	endrule

	rule bclr_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Bclr, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.and_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// bext
	rule bext_1(args.first matches AluRequest { inst: tagged Binary { op: Bext, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: ?,
			arithmetic: ?,
			w: ?
		});
	endrule

	rule bext_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Bext, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate & 1,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// binv
	rule binv_1(args.first matches AluRequest { inst: tagged Binary { op: Binv, rs1: .rs1, rs2: .rs2 } });
		UInt#(64) rs2u = unpack(pack(rs2));
		UInt#(6) rs2_shamt = truncate(rs2u);
		Int#(64) rs2_decoded = 1 << rs2_shamt;
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2_decoded,
			invert_arg2: False
		});
	endrule

	rule binv_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Binv, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.xor_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// bset
	rule bset_1(args.first matches AluRequest { inst: tagged Binary { op: Bset, rs1: .rs1, rs2: .rs2 } });
		UInt#(64) rs2u = unpack(pack(rs2));
		UInt#(6) rs2_shamt = truncate(rs2u);
		Int#(64) rs2_decoded = 1 << rs2_shamt;
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2_decoded,
			invert_arg2: False
		});
	endrule

	rule bset_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Bset, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.or_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// branch
	rule branch_1(args.first matches AluRequest { pc: .pc, inst: tagged Branch { offset: .offset } });
		adder.request.put(AdderRequest {
			arg1: pc,
			arg2: extend(offset),
			cin: False
		});
	endrule

	rule branch_2(args.first matches AluRequest { inst: tagged Branch { op: .op, rs1: .rs1, rs2: .rs2 } });
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

	rule branch_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Branch { op: .op } });
		let cmp_response = cmp.response.first;
		let jump = case (op) matches
			tagged Equal: return cmp_response.eq;
			tagged NotEqual: return !cmp_response.eq;
			tagged LessThan: return cmp_response.lt;
			tagged GreaterThanOrEqual: return !cmp_response.lt;
			tagged LessThanUnsigned: return cmp_response.lt;
			tagged GreaterThanOrEqualUnsigned: return !cmp_response.lt;
		endcase;
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: 0,
			x_regs_rd_value: ?,
			csrd: tagged Invalid,
			next_pc: jump ? adder_response.add : next_pc
		});
	endrule

	// csrrw
	rule csrrw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Csr { op: Csrrw, rd: .rd, csrd: .csrd, csrs: .csrs, rs2: .rs2 } });
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: csrs,
			csrd: tagged Valid tuple2(csrd, rs2),
			next_pc: next_pc
		});
	endrule

	// csrrs
	rule csrrs_1(args.first matches AluRequest { inst: tagged Csr { op: Csrrs, csrd: .csrd, csrs: .csrs, rs2: .rs2 } } &&& csrd != 0);
		logical.request.put(LogicalRequest {
			arg1: csrs,
			arg2: rs2,
			invert_arg2: False
		});
	endrule

	rule csrr_end1(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Csr { op: Csrrs, rd: .rd, csrd: 0, csrs: .csrs } });
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: csrs,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	rule csrrs_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Csr { op: Csrrs, rd: .rd, csrd: .csrd, csrs: .csrs } } &&& csrd != 0);
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: csrs,
			csrd: csrd == 0 ? tagged Invalid : tagged Valid tuple2(csrd, logical_response.or_),
			next_pc: next_pc
		});
	endrule

	// csrrc
	rule csrrc_1(args.first matches AluRequest { inst: tagged Csr { op: Csrrc, csrd: .csrd, csrs: .csrs, rs2: .rs2 } } &&& csrd != 0);
		logical.request.put(LogicalRequest {
			arg1: csrs,
			arg2: rs2,
			invert_arg2: True
		});
	endrule

	rule csrr_end2(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Csr { op: Csrrc, rd: .rd, csrd: 0, csrs: .csrs } });
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: csrs,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	rule csrrc_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Csr { op: Csrrc, rd: .rd, csrd: .csrd, csrs: .csrs } } &&& csrd != 0);
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: csrs,
			csrd: csrd == 0 ? tagged Invalid : tagged Valid tuple2(csrd, logical_response.and_),
			next_pc: next_pc
		});
	endrule

	// clz
	rule clz_1(args.first matches AluRequest { inst: tagged Unary { op: Clz, rs: .rs } });
		adder.request.put(AdderRequest {
			arg1: unpack(reverseBits(pack(rs))),
			arg2: -1,
			cin: False
		});
	endrule

	rule clz_2(args.first matches AluRequest { inst: tagged Unary { op: Clz, rs: .rs } });
		let adder_response = adder.response.first;
		logical.request.put(LogicalRequest {
			arg1: adder_response.add,
			arg2: unpack(reverseBits(pack(rs))),
			invert_arg2: True
		});
	endrule

	rule clz_3(args.first matches AluRequest { inst: tagged Unary { op: Clz } });
		let logical_response = logical.response.first;
		popcnt.request.put(PopcntRequest {
			arg: logical_response.and_
		});
	endrule

	rule clz_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Clz, rd: .rd } });
		let popcnt_response = popcnt.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: popcnt_response.cpop,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// clzw
	rule clzw_1(args.first matches AluRequest { inst: tagged Unary { op: Clzw, rs: .rs } });
		adder.request.put(AdderRequest {
			arg1: unpack(reverseBits(pack(rs))),
			arg2: -1,
			cin: False
		});
	endrule

	rule clzw_2(args.first matches AluRequest { inst: tagged Unary { op: Clzw, rs: .rs } });
		let adder_response = adder.response.first;
		logical.request.put(LogicalRequest {
			arg1: adder_response.add,
			arg2: unpack(reverseBits(pack(rs))),
			invert_arg2: True
		});
	endrule

	rule clzw_3(args.first matches AluRequest { inst: tagged Unary { op: Clzw } });
		let logical_response = logical.response.first;
		popcnt.request.put(PopcntRequest {
			arg: logical_response.and_
		});
	endrule

	rule clzw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Clzw, rd: .rd } });
		let popcnt_response = popcnt.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: popcnt_response.cpopw,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// cpop
	rule cpop_1(args.first matches AluRequest { inst: tagged Unary { op: Cpop, rs: .rs } });
		popcnt.request.put(PopcntRequest {
			arg: rs
		});
	endrule

	rule cpop_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Cpop, rd: .rd } });
		let popcnt_response = popcnt.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: popcnt_response.cpop,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// cpopw
	rule cpopw_1(args.first matches AluRequest { inst: tagged Unary { op: Cpopw, rs: .rs } });
		popcnt.request.put(PopcntRequest {
			arg: rs
		});
	endrule

	rule cpopw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Cpopw, rd: .rd } });
		let popcnt_response = popcnt.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: popcnt_response.cpopw,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// ctz
	rule ctz_1(args.first matches AluRequest { inst: tagged Unary { op: Ctz, rs: .rs } });
		adder.request.put(AdderRequest {
			arg1: rs,
			arg2: -1,
			cin: False
		});
	endrule

	rule ctz_2(args.first matches AluRequest { inst: tagged Unary { op: Ctz, rs: .rs } });
		let adder_response = adder.response.first;
		logical.request.put(LogicalRequest {
			arg1: adder_response.add,
			arg2: rs,
			invert_arg2: True
		});
	endrule

	rule ctz_3(args.first matches AluRequest { inst: tagged Unary { op: Ctz } });
		let logical_response = logical.response.first;
		popcnt.request.put(PopcntRequest {
			arg: logical_response.and_
		});
	endrule

	rule ctz_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Ctz, rd: .rd } });
		let popcnt_response = popcnt.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: popcnt_response.cpop,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// ctzw
	rule ctzw_1(args.first matches AluRequest { inst: tagged Unary { op: Ctzw, rs: .rs } });
		adder.request.put(AdderRequest {
			arg1: rs,
			arg2: -1,
			cin: False
		});
	endrule

	rule ctzw_2(args.first matches AluRequest { inst: tagged Unary { op: Ctzw, rs: .rs } });
		let adder_response = adder.response.first;
		logical.request.put(LogicalRequest {
			arg1: adder_response.add,
			arg2: rs,
			invert_arg2: True
		});
	endrule

	rule ctzw_3(args.first matches AluRequest { inst: tagged Unary { op: Ctzw } });
		let logical_response = logical.response.first;
		popcnt.request.put(PopcntRequest {
			arg: logical_response.and_
		});
	endrule

	rule ctzw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Ctzw, rd: .rd } });
		let popcnt_response = popcnt.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: popcnt_response.cpopw,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// czero.eqz
	rule czero_eqz_1(args.first matches AluRequest { inst: tagged Binary { op: CzeroEqz, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: 0,
			arg2: rs2,
			signed_: ?
		});
	endrule

	rule czero_eqz_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: CzeroEqz, rd: .rd, rs1: .rs1 } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.eq ? 0 : rs1,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// czero.nez
	rule czero_nez_1(args.first matches AluRequest { inst: tagged Binary { op: CzeroNez, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: 0,
			arg2: rs2,
			signed_: ?
		});
	endrule

	rule czero_nez_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: CzeroNez, rd: .rd, rs1: .rs1 } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.eq ? rs1 : 0,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// fence
	rule fence_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Fence });
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: 0,
			x_regs_rd_value: ?,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// jal, jalr
	rule jal_1(args.first matches AluRequest { pc: .pc, inst: tagged Jal { base: tagged Pc, offset: .offset } });
		adder.request.put(AdderRequest {
			arg1: pc,
			arg2: extend(offset),
			cin: False
		});
	endrule

	rule jal_2(args.first matches AluRequest { inst: tagged Jal { base: tagged XReg .base, offset: .offset } });
		adder.request.put(AdderRequest {
			arg1: base,
			arg2: extend(offset),
			cin: False
		});
	endrule

	rule jal_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Jal { rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: next_pc,
			csrd: tagged Invalid,
			next_pc: adder_response.add
		});
	endrule

	// lui
	rule li_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Li { rd: .rd, imm: .imm } });
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: extend(imm),
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// max
	rule max_1(args.first matches AluRequest { inst: tagged Binary { op: Max, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: True
		});
	endrule

	rule max_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Max, rd: .rd, rs1: .rs1, rs2: .rs2 } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? rs2 : rs1,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// maxu
	rule maxu_1(args.first matches AluRequest { inst: tagged Binary { op: Maxu, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: False
		});
	endrule

	rule maxu_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Maxu, rd: .rd, rs1: .rs1, rs2: .rs2 } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? rs2 : rs1,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// min
	rule min_1(args.first matches AluRequest { inst: tagged Binary { op: Min, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: True
		});
	endrule

	rule min_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Min, rd: .rd, rs1: .rs1, rs2: .rs2 } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? rs1 : rs2,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// minu
	rule minu_1(args.first matches AluRequest { inst: tagged Binary { op: Minu, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: False
		});
	endrule

	rule minu_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Minu, rd: .rd, rs1: .rs1, rs2: .rs2 } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? rs1 : rs2,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// mul
	rule mul_1(args.first matches AluRequest { inst: tagged Binary { op: Mul, rs1: .rs1, rs2: .rs2 } });
		multiplier.request.put(MultiplierRequest {
			arg1: rs1,
			arg1_is_signed: True,
			arg2: rs2,
			arg2_is_signed: True
		});
	endrule

	rule mul_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Mul, rd: .rd } });
		let multiplier_response = multiplier.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: multiplier_response.mul,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// mulh
	rule mulh_1(args.first matches AluRequest { inst: tagged Binary { op: Mulh, rs1: .rs1, rs2: .rs2 } });
		multiplier.request.put(MultiplierRequest {
			arg1: rs1,
			arg1_is_signed: True,
			arg2: rs2,
			arg2_is_signed: True
		});
	endrule

	rule mulh_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Mulh, rd: .rd } });
		let multiplier_response = multiplier.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: multiplier_response.mulh,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// mulhsu
	rule mulhsu_1(args.first matches AluRequest { inst: tagged Binary { op: Mulhsu, rs1: .rs1, rs2: .rs2 } });
		multiplier.request.put(MultiplierRequest {
			arg1: rs1,
			arg1_is_signed: True,
			arg2: rs2,
			arg2_is_signed: False
		});
	endrule

	rule mulhsu_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Mulhsu, rd: .rd } });
		let multiplier_response = multiplier.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: multiplier_response.mulh,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// mulhu
	rule mulhu_1(args.first matches AluRequest { inst: tagged Binary { op: Mulhu, rs1: .rs1, rs2: .rs2 } });
		multiplier.request.put(MultiplierRequest {
			arg1: rs1,
			arg1_is_signed: False,
			arg2: rs2,
			arg2_is_signed: False
		});
	endrule

	rule mulhu_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Mulhu, rd: .rd } });
		let multiplier_response = multiplier.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: multiplier_response.mulh,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// mulw
	rule mulw_1(args.first matches AluRequest { inst: tagged Binary { op: Mulw, rs1: .rs1, rs2: .rs2 } });
		multiplier.request.put(MultiplierRequest {
			arg1: rs1,
			arg1_is_signed: True,
			arg2: rs2,
			arg2_is_signed: True
		});
	endrule

	rule mulw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Mulw, rd: .rd } });
		let multiplier_response = multiplier.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: multiplier_response.mulw,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// or
	rule or_1(args.first matches AluRequest { inst: tagged Binary { op: Or, rs1: .rs1, rs2: .rs2 } });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2,
			invert_arg2: False
		});
	endrule

	rule or_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Or, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.or_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// orc.b
	rule orc_b_1(args.first matches AluRequest { inst: tagged Unary { op: OrcB, rs: .rs } });
		orc_b.request.put(OrcBRequest {
			arg: rs
		});
	endrule

	rule orc_b_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: OrcB, rd: .rd } });
		let orc_b_response = orc_b.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: orc_b_response.orc_b,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// orn
	rule orn_1(args.first matches AluRequest { inst: tagged Binary { op: Orn, rs1: .rs1, rs2: .rs2 } });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2,
			invert_arg2: True
		});
	endrule

	rule orn_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Orn, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.or_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// rev8
	rule rev8_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: Rev8, rd: .rd, rs: .rs } });
		let rs_bits = pack(rs);
		let rev8_response = unpack({
			rs_bits[7:0],
			rs_bits[15:8],
			rs_bits[23:16],
			rs_bits[31:24],
			rs_bits[39:32],
			rs_bits[47:40],
			rs_bits[55:48],
			rs_bits[63:56]
		});
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: rev8_response,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// rol
	rule rol_1(args.first matches AluRequest { inst: tagged Binary { op: Rol, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: False,
			rotate: True,
			arithmetic: ?,
			w: False
		});
	endrule

	rule rol_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Rol, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// rolw
	rule rolw_1(args.first matches AluRequest { inst: tagged Binary { op: Rolw, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: False,
			rotate: True,
			arithmetic: ?,
			w: True
		});
	endrule

	rule rolw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Rolw, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// ror
	rule ror_1(args.first matches AluRequest { inst: tagged Binary { op: Ror, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: True,
			arithmetic: ?,
			w: False
		});
	endrule

	rule ror_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Ror, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// rorw
	rule rorw_1(args.first matches AluRequest { inst: tagged Binary { op: Rorw, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: True,
			arithmetic: ?,
			w: True
		});
	endrule

	rule rorw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Rorw, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sext.b
	rule sext_b_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: SextB, rd: .rd, rs: .rs } });
		Int#(8) rs_ = truncate(rs);
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: extend(rs_),
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sext.h
	rule sext_h_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: SextH, rd: .rd, rs: .rs } });
		Int#(16) rs_ = truncate(rs);
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: extend(rs_),
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sh1add
	rule sh1add_1(args.first matches AluRequest { inst: tagged Binary { op: Sh1add, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1 << 1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule sh1add_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sh1add, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sh1add.uw
	rule sh1add_uw_1(args.first matches AluRequest { inst: tagged Binary { op: Sh1addUw, rs1: .rs1, rs2: .rs2 } });
		Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));
		adder.request.put(AdderRequest {
			arg1: rs1uw << 1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule sh1add_uw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sh1addUw, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sh2add
	rule sh2add_1(args.first matches AluRequest { inst: tagged Binary { op: Sh2add, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1 << 1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule sh2add_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sh2add, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sh2add.uw
	rule sh2add_uw_1(args.first matches AluRequest { inst: tagged Binary { op: Sh2addUw, rs1: .rs1, rs2: .rs2 } });
		Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));
		adder.request.put(AdderRequest {
			arg1: rs1uw << 2,
			arg2: rs2,
			cin: False
		});
	endrule

	rule sh2add_uw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sh2addUw, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sh3add
	rule sh3add_1(args.first matches AluRequest { inst: tagged Binary { op: Sh3add, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1 << 1,
			arg2: rs2,
			cin: False
		});
	endrule

	rule sh3add_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sh3add, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sh3add.uw
	rule sh3add_uw_1(args.first matches AluRequest { inst: tagged Binary { op: Sh3addUw, rs1: .rs1, rs2: .rs2 } });
		Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));
		adder.request.put(AdderRequest {
			arg1: rs1uw << 3,
			arg2: rs2,
			cin: False
		});
	endrule

	rule sh3add_uw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sh3addUw, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sll
	rule sll_1(args.first matches AluRequest { inst: tagged Binary { op: Sll, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: False,
			rotate: False,
			arithmetic: ?,
			w: False
		});
	endrule

	rule sll_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sll, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sll.uw
	rule sll_uw_1(args.first matches AluRequest { inst: tagged Binary { op: SllUw, rs1: .rs1, rs2: .rs2 } });
		Int#(64) rs1uw = unpack(zeroExtend(pack(rs1)[31:0]));
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1uw,
			shamt: rs2,
			right: False,
			rotate: False,
			arithmetic: ?,
			w: False
		});
	endrule

	rule sll_uw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: SllUw, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sllw
	rule sllw_1(args.first matches AluRequest { inst: tagged Binary { op: Sllw, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: False,
			rotate: False,
			arithmetic: ?,
			w: True
		});
	endrule

	rule sllw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sllw, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sra
	rule sra_1(args.first matches AluRequest { inst: tagged Binary { op: Sra, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: False,
			arithmetic: True,
			w: False
		});
	endrule

	rule sra_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sra, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sraw
	rule sraw_1(args.first matches AluRequest { inst: tagged Binary { op: Sraw, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: False,
			arithmetic: True,
			w: True
		});
	endrule

	rule sraw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sraw, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// srl
	rule srl_1(args.first matches AluRequest { inst: tagged Binary { op: Srl, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: False,
			arithmetic: False,
			w: False
		});
	endrule

	rule srl_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Srl, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// srlw
	rule srlw_1(args.first matches AluRequest { inst: tagged Binary { op: Srlw, rs1: .rs1, rs2: .rs2 } });
		shift_rotate.request.put(ShiftRotateRequest {
			value: rs1,
			shamt: rs2,
			right: True,
			rotate: False,
			arithmetic: False,
			w: True
		});
	endrule

	rule srlw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Srlw, rd: .rd } });
		let shift_rotate_response = shift_rotate.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: shift_rotate_response.shift_rotate,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// slt
	rule slt_1(args.first matches AluRequest { inst: tagged Binary { op: Slt, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: True
		});
	endrule

	rule slt_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Slt, rd: .rd } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? 1 : 0,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sltu
	rule sltu_1(args.first matches AluRequest { inst: tagged Binary { op: Sltu, rs1: .rs1, rs2: .rs2 } });
		cmp.request.put(CmpRequest {
			arg1: rs1,
			arg2: rs2,
			signed_: False
		});
	endrule

	rule sltu_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sltu, rd: .rd } });
		let cmp_response = cmp.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: cmp_response.lt ? 1 : 0,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// sub
	rule sub_1(args.first matches AluRequest { inst: tagged Binary { op: Sub, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: ~rs2,
			cin: True
		});
	endrule

	rule sub_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Sub, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.add,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// subw
	rule subw_1(args.first matches AluRequest { inst: tagged Binary { op: Subw, rs1: .rs1, rs2: .rs2 } });
		adder.request.put(AdderRequest {
			arg1: rs1,
			arg2: ~rs2,
			cin: True
		});
	endrule

	rule subw_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Subw, rd: .rd } });
		let adder_response = adder.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: adder_response.addw,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// xnor
	rule xnor_1(args.first matches AluRequest { inst: tagged Binary { op: Xnor, rs1: .rs1, rs2: .rs2 } });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2,
			invert_arg2: True
		});
	endrule

	rule xnor_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Xnor, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.xor_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// xor
	rule xor_1(args.first matches AluRequest { inst: tagged Binary { op: Xor, rs1: .rs1, rs2: .rs2 } });
		logical.request.put(LogicalRequest {
			arg1: rs1,
			arg2: rs2,
			invert_arg2: False
		});
	endrule

	rule xor_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Binary { op: Xor, rd: .rd } });
		let logical_response = logical.response.first;
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: logical_response.xor_,
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	// zext.h
	rule zext_h_end(args.first matches AluRequest { next_pc: .next_pc, inst: tagged Unary { op: ZextH, rd: .rd, rs: .rs } });
		Int#(16) rs_ = truncate(rs);
		result.put(tagged Ok AluResponseOk {
			x_regs_rd: rd,
			x_regs_rd_value: zeroExtend(rs_),
			csrd: tagged Invalid,
			next_pc: next_pc
		});
	endrule

	interface request = toPut(args_);

	interface GetS response;
		method AluResponse first = result_.first;

		method Action deq;
			args_.deq;
			adder.response.deq;
			cmp.response.deq;
			logical.response.deq;
			multiplier.response.deq;
			orc_b.response.deq;
			popcnt.response.deq;
			shift_rotate.response.deq;
			result_.deq;
		endmethod
	endinterface
endmodule

typedef Server#(AdderRequest#(width), AdderResponse#(width)) Adder#(numeric type width);

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
module mkAdder(Adder#(64));
	FIFO#(AdderRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(AdderRequest#(64)) args = fifoToGetS(args_);
	FIFO#(AdderResponse#(64)) result_ <- mkBypassFIFO;
	Put#(AdderResponse#(64)) result = toPut(result_);

	rule run(args.first matches AdderRequest { arg1: .arg1, arg2: .arg2, cin: .cin });
		let add = add_inner(arg1, arg2, cin);
		Int#(32) addw = truncate(add);
		result.put(AdderResponse {
			add: add,
			addw: extend(addw)
		});
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Int#(width) add_inner(Int#(width) arg1, Int#(width) arg2, Bool cin) =
	arg1 + arg2 + (cin ? 1 : 0);

typedef Server#(CmpRequest#(width), CmpResponse) Cmp#(numeric type width);

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
module mkCmp(Cmp#(64));
	FIFO#(CmpRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(CmpRequest#(64)) args = fifoToGetS(args_);
	FIFO#(CmpResponse) result_ <- mkBypassFIFO;
	Put#(CmpResponse) result = toPut(result_);

	rule run(args.first matches CmpRequest { arg1: .arg1, arg2: .arg2, signed_: .signed_ });
		result.put(cmp_inner(pack(arg1), pack(arg2), signed_));
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
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

typedef Server#(LogicalRequest#(width), LogicalResponse#(width)) Logical#(numeric type width);

typedef struct {
	Int#(width) arg1;
	Int#(width) arg2;
	Bool invert_arg2;
} LogicalRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) and_;
	Int#(width) or_;
	Int#(width) xor_;
} LogicalResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkLogical(Logical#(64));
	FIFO#(LogicalRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(LogicalRequest#(64)) args = fifoToGetS(args_);
	FIFO#(LogicalResponse#(64)) result_ <- mkBypassFIFO;
	Put#(LogicalResponse#(64)) result = toPut(result_);

	rule run(args.first matches LogicalRequest { arg1: .arg1, arg2: .arg2, invert_arg2: .invert_arg2 });
		result.put(logical_inner(arg1, arg2, invert_arg2));
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function LogicalResponse#(width) logical_inner(Int#(width) arg1, Int#(width) arg2, Bool invert_arg2);
	let arg2_ = invert_arg2 ? ~arg2 : arg2;
	let and_ = arg1 & arg2_;
	let or_ = arg1 | arg2_;
	return LogicalResponse {
		and_: and_,
		or_: or_,
		xor_: ~(and_ | ~or_)
	};
endfunction

typedef Server#(MultiplierRequest#(width), MultiplierResponse#(width)) Multiplier#(numeric type width);

typedef struct {
	Int#(width) arg1;
	Bool arg1_is_signed;
	Int#(width) arg2;
	Bool arg2_is_signed;
} MultiplierRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) mulh;
	Int#(width) mul;
	Int#(width) mulw;
} MultiplierResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkMultiplier(Multiplier#(64));
	FIFO#(MultiplierRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(MultiplierRequest#(64)) args = fifoToGetS(args_);
	FIFO#(MultiplierResponse#(64)) result_ <- mkBypassFIFO;
	Put#(MultiplierResponse#(64)) result = toPut(result_);

	rule run(args.first matches MultiplierRequest { arg1: .arg1, arg1_is_signed: .arg1_is_signed, arg2: .arg2, arg2_is_signed: .arg2_is_signed });
		result.put(multiplier_inner(arg1, arg1_is_signed, arg2, arg2_is_signed));
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function MultiplierResponse#(width) multiplier_inner(Int#(width) arg1, Bool arg1_is_signed, Int#(width) arg2, Bool arg2_is_signed)
provisos (
	Add#(a__, TDiv#(width, 2), width),
	Add#(b__, TDiv#(width, 2), TMul#(width, 2)),
	Add#(c__, width, TMul#(width, 2))
);
	Int#(TMul#(width, 2)) arg1_ = arg1_is_signed ? signExtend(arg1) : zeroExtend(arg1);
	Int#(TMul#(width, 2)) arg2_ = arg2_is_signed ? signExtend(arg2) : zeroExtend(arg2);
	let product = arg1_ * arg2_;
	Int#(TDiv#(width, 2)) mulw = truncate(product);
	match { .mulh, .mul } = split(pack(product));
	return MultiplierResponse { mulh: unpack(mulh), mul: unpack(mul), mulw: extend(mulw) };
endfunction

typedef Server#(OrcBRequest#(width), OrcBResponse#(width)) OrcB#(numeric type width);

typedef struct {
	Int#(width) arg;
} OrcBRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) orc_b;
} OrcBResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkOrcB(OrcB#(64));
	FIFO#(OrcBRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(OrcBRequest#(64)) args = fifoToGetS(args_);
	FIFO#(OrcBResponse#(64)) result_ <- mkBypassFIFO;
	Put#(OrcBResponse#(64)) result = toPut(result_);

	rule run(args.first matches OrcBRequest { arg: .arg });
		result.put(OrcBResponse {
			orc_b: unpack(orc_b_inner(pack(arg)))
		});
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
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

typedef Server#(PopcntRequest#(width), PopcntResponse#(width)) Popcnt#(numeric type width);

typedef struct {
	Int#(width) arg;
} PopcntRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) cpop;
	Int#(width) cpopw;
} PopcntResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkPopcnt(Popcnt#(64));
	FIFO#(PopcntRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(PopcntRequest#(64)) args = fifoToGetS(args_);
	FIFO#(PopcntResponse#(64)) result_ <- mkBypassFIFO;
	Put#(PopcntResponse#(64)) result = toPut(result_);

	rule run(args.first matches PopcntRequest { arg: .arg });
		Tuple2#(Bit#(32), Bit#(32)) arg_parts = split(pack(arg));
		match { .arg_hi, .arg_lo } = arg_parts;
		UInt#(7) cpop_lo = extend(popcnt_inner(arg_lo));
		UInt#(7) cpop_hi = extend(popcnt_inner(arg_hi));
		result.put(PopcntResponse {
			cpop: unpack(pack(extend(cpop_lo + cpop_hi))),
			cpopw: unpack(pack(extend(cpop_lo)))
		});
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

typeclass PopcntInner#(numeric type width);
	function UInt#(TLog#(TAdd#(width, 1))) popcnt_inner(Bit#(width) arg);
endtypeclass

instance PopcntInner#(1);
	function UInt#(1) popcnt_inner(Bit#(1) arg) = unpack(arg);
endinstance

instance PopcntInner#(width)
provisos (
	Div#(width, 2, hi_width),
	Add#(hi_width, lo_width, width),
	Add#(TLog#(TAdd#(hi_width, 1)), a__, TLog#(TAdd#(width, 1))),
	Add#(TLog#(TAdd#(lo_width, 1)), b__, TLog#(TAdd#(width, 1))),
	PopcntInner#(hi_width),
	PopcntInner#(lo_width)
);
	function UInt#(TLog#(TAdd#(width, 1))) popcnt_inner(Bit#(width) arg);
		Tuple2#(Bit#(hi_width), Bit#(lo_width)) arg_parts = split(arg);
		match { .arg_hi, .arg_lo } = arg_parts;
		UInt#(TLog#(TAdd#(width, 1))) hi = extend(popcnt_inner(arg_hi));
		UInt#(TLog#(TAdd#(width, 1))) lo = extend(popcnt_inner(arg_lo));
		return hi + lo;
	endfunction
endinstance

typedef Server#(ShiftRotateRequest#(width), ShiftRotateResponse#(width)) ShiftRotate#(numeric type width);

typedef struct {
	Int#(width) value;
	Int#(width) shamt;
	Bool right;
	Bool rotate;
	Bool arithmetic;
	Bool w;
} ShiftRotateRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) shift_rotate;
} ShiftRotateResponse#(numeric type width) deriving(Bits);

module mkShiftRotate(ShiftRotate#(64));
	FIFO#(ShiftRotateRequest#(64)) args_ <- mkBypassFIFO;
	GetS#(ShiftRotateRequest#(64)) args = fifoToGetS(args_);
	FIFO#(ShiftRotateResponse#(64)) result_ <- mkBypassFIFO;
	Put#(ShiftRotateResponse#(64)) result = toPut(result_);

	rule run(args.first matches ShiftRotateRequest { value: .value, shamt: .shamt, right: .right, rotate: .rotate, arithmetic: .arithmetic, w: .w });
		Bit#(6) shamt_ = truncate(pack(shamt));
		result.put(ShiftRotateResponse {
			shift_rotate: shift_rotate_inner(value, shamt_, right, rotate, arithmetic, w)
		});
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
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
	function ShiftInnerRoundResponse#(width) shift_rotate_inner_round(
		Bit#(shamt_width) shamt,
		Bool right,
		Bool rotate,
		Integer i,
		Bit#(width) r,
		Bit#(width) p
	);
endtypeclass

instance ShiftInnerRound#(width, 0);
	function ShiftInnerRoundResponse#(width) shift_rotate_inner_round(
		Bit#(0) shamt,
		Bool right,
		Bool rotate,
		Integer i,
		Bit#(width) r,
		Bit#(width) p
	) = ShiftInnerRoundResponse { r: r, p: p };
endinstance

instance ShiftInnerRound#(width, shamt_width)
provisos (
	Add#(a__, 1, width),
	ShiftInnerRound#(width, TSub#(shamt_width, 1))
);
	function ShiftInnerRoundResponse#(width) shift_rotate_inner_round(
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
} ShiftInnerRoundResponse#(numeric type width) deriving(Bits);
