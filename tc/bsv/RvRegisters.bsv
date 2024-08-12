import Vector::*;

import RvCommon::*;

interface RvRegisters;
	method Instruction#(Int#(32), Int#(32)) load(Instruction#(XReg, Either#(XReg, Int#(12))) inst);
	method Action store(XReg rd, Int#(32) rd_value);
endinterface

(* synthesize *)
module mkRvRegisters(RvRegisters);
	Vector#(32, Reg#(Int#(32))) x_regs <- replicateM(mkReg(0));

	method Instruction#(Int#(32), Int#(32)) load(Instruction#(XReg, Either#(XReg, Int#(12))) inst);
		case (inst) matches
			tagged Auipc { rd: .rd, imm: .imm }: return tagged Auipc {
				rd: rd,
				imm: imm
			};

			tagged Binary { op: .op, rd: .rd, rs1: .rs1, rs2: .rs2 }: return tagged Binary {
				op: op,
				rd: rd,
				rs1: x_regs[rs1],
				rs2: load_x_reg(x_regs, rs2)
			};

			tagged Branch { op: .op, rs1: .rs1, rs2: .rs2, offset: .offset }: return tagged Branch {
				op: op,
				rs1: x_regs[rs1],
				rs2: load_x_reg(x_regs, rs2),
				offset: offset
			};

			tagged Ebreak: return tagged Ebreak;

			tagged Fence: return tagged Fence;

			tagged Jal { rd: .rd, base: tagged Pc, offset: .offset }: return tagged Jal {
				rd: rd,
				base: tagged Pc,
				offset: offset
			};

			tagged Jal { rd: .rd, base: tagged XReg .base, offset: .offset }: return tagged Jal {
				rd: rd,
				base: tagged XReg x_regs[base],
				offset: offset
			};

			tagged Li { rd: .rd, imm: .imm }: return tagged Li {
				rd: rd,
				imm: imm
			};

			tagged Load { op: .op, rd: .rd, base: .base, offset: .offset }: return tagged Load {
				op: op,
				rd: rd,
				base: x_regs[base],
				offset: offset
			};

			tagged Store { op: .op, base: .base, value: .value, offset: .offset }: return tagged Store {
				op: op,
				base: x_regs[base],
				value: load_x_reg(x_regs, value),
				offset: offset
			};
		endcase
	endmethod

	method Action store(XReg rd, Int#(32) rd_value);
		if (rd != 0)
			x_regs[rd] <= rd_value;
	endmethod
endmodule

function Int#(32) load_x_reg(Vector#(32, Reg#(Int#(32))) x_regs, Either#(XReg, Int#(12)) rs);
	case (rs) matches
		tagged Left .rs: return x_regs[rs];
		tagged Right .imm: return extend(imm);
	endcase
endfunction
