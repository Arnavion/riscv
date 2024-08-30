import Vector::*;

import RvCommon::*;

interface RvRegisters;
	method Instruction#(Int#(64), Int#(64), Int#(64)) load(Instruction#(XReg, Either#(XReg, Int#(12)), Csr) inst, Int#(64) csr_time);
	method ActionValue#(Bool) store(XReg rd, Int#(64) rd_value, Maybe#(Tuple2#(Csr, Int#(64))) csrd);
	method Action retire(Int#(64) instret);
endinterface

(* synthesize *)
module mkRvRegisters(RvRegisters);
	Vector#(32, Reg#(Int#(64))) x_regs <- replicateM(mkReg(0));
	Reg#(Int#(64)) csr_cycle <- mkReg(0);
	Reg#(Int#(64)) csr_instret <- mkReg(0);

	rule csr_cycle_increment;
		csr_cycle <= csr_cycle + 1;
	endrule

	method Instruction#(Int#(64), Int#(64), Int#(64)) load(Instruction#(XReg, Either#(XReg, Int#(12)), Csr) inst, Int#(64) csr_time);
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

			tagged Csr { op: .op, rd: .rd, csrd: .csrd, csrs: .csrs, rs2: .rs2 }: case (op) matches
				Csrrw: return tagged Csr {
					op: Csrrw,
					rd: rd,
					csrd: csrd,
					csrs: rd == 0 ? ? : load_csr(csr_cycle, csr_instret, csr_time, csrs),
					rs2: load_x_reg(x_regs, rs2)
				};
				Csrrs: return tagged Csr {
					op: Csrrs,
					rd: rd,
					csrd: csrd,
					csrs: csrd == 0 ? ? : load_csr(csr_cycle, csr_instret, csr_time, csrs),
					rs2: load_x_reg(x_regs, rs2)
				};
				Csrrc: return tagged Csr {
					op: Csrrc,
					rd: rd,
					csrd: csrd,
					csrs: csrd == 0 ? ? : load_csr(csr_cycle, csr_instret, csr_time, csrs),
					rs2: load_x_reg(x_regs, rs2)
				};
			endcase

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

	method ActionValue#(Bool) store(XReg rd, Int#(64) rd_value, Maybe#(Tuple2#(Csr, Int#(64))) csrd);
		let fault = False;

		if (rd != 0)
			x_regs[rd] <= rd_value;

		if (csrd matches tagged Valid { .csrd_, .csrd_value })
			case (csrd_) matches
				default: fault = True;
			endcase

		return fault;
	endmethod

	method Action retire(Int#(64) instret);
		csr_instret <= csr_instret + instret;
	endmethod
endmodule

function Int#(64) load_x_reg(Vector#(32, Reg#(Int#(64))) x_regs, Either#(XReg, Int#(12)) rs);
	case (rs) matches
		tagged Left .rs: return x_regs[rs];
		tagged Right .imm: return extend(imm);
	endcase
endfunction

function Int#(64) load_csr(Reg#(Int#(64)) csr_cycle, Reg#(Int#(64)) csr_instret, Int#(64) csr_time, Csr csrs);
	case (csrs) matches
		12'h301: return unpack({
			2'b10, // XLEN = 64
			'0,
			1'b0, // Reserved
			1'b0, // Reserved
			1'b0, // X
			1'b0, // Reserved
			1'b0, // V
			1'b0, // U
			1'b0, // Reserved
			1'b0, // S
			1'b0, // Reserved
			1'b0, // Q
			1'b0, // Reserved
			1'b0, // Reserved
			1'b0, // Reserved
			1'b0, // M
			1'b0, // Reserved
			1'b0, // Reserved
			1'b0, // Reserved
			1'b1, // I
			1'b0, // H
			1'b0, // Reserved
			1'b0, // F
			1'b0, // E
			1'b0, // D
			1'b1, // C
			1'b0, // B
			1'b0  // A
		});
		12'hc00: return csr_cycle;
		12'hc01: return csr_time;
		12'hc02: return csr_instret;
		default: return 0;
	endcase
endfunction
