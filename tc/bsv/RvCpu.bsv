import Vector::*;

import RvAlu::*;
import RvCommon::*;
import RvDecoder::*;

interface RvCpu;
	method Action feed(Bit#(32) in);
	method InspectResult inspect;
endinterface

typedef struct {
	State state;
	Int#(32) pc;
	Vector#(32, Int#(32)) x_regs;
} InspectResult deriving(Bits);

typedef union tagged {
	void Running;
	void Sigill;
	void Efault;
} State deriving(Bits);

(* synthesize *)
module mkRvCpu(RvCpu);
	Reg#(State) state <- mkReg(tagged Running);
	Reg#(Int#(32)) pc <- mkReg(0);
	Vector#(32, Reg#(Int#(32))) x_regs <- replicateM(mkReg(0));

	RvAlu alu <- mkRvAlu;
	RvDecoder decoder <- mkRvDecoder;

	method Action feed(Bit#(32) in) if (state matches Running);
		case (decode(decoder, in)) matches
			tagged Invalid: state <= tagged Sigill;

			tagged Valid .inst: begin
				let x_regs_ = readVReg(x_regs);

				Instruction#(Int#(32)) ready_inst = case (inst) matches
					tagged Auipc { rd: .rd, imm: .imm }: return tagged Auipc {
						rd: rd,
						imm: imm
					};

					tagged Binary { op: .op, rd: .rd, rs1: .rs1, rs2: .rs2 }: return tagged Binary {
						op: op,
						rd: rd,
						rs1: fetch_x_reg(x_regs_, rs1),
						rs2: fetch_x_reg(x_regs_, rs2)
					};

					tagged Branch { op: .op, rs1: .rs1, rs2: .rs2, imm: .imm }: return tagged Branch {
						op: op,
						rs1: fetch_x_reg(x_regs_, rs1),
						rs2: fetch_x_reg(x_regs_, rs2),
						imm: imm
					};

					tagged Ebreak: return tagged Ebreak;

					tagged Fence: return tagged Fence;

					tagged Jal { op: tagged Pc { offset: .offset }, rd: .rd }: return tagged Jal {
						op: tagged Pc { offset: offset },
						rd: rd
					};

					tagged Jal { op: tagged XReg { base: .base, offset: .offset }, rd: .rd }: return tagged Jal {
						op: tagged XReg { base: fetch_x_reg(x_regs_, base), offset: offset },
						rd: rd
					};

					tagged Load { op: .op, rd: .rd, base: .base, offset: .offset }: return tagged Load {
						op: op,
						rd: rd,
						base: fetch_x_reg(x_regs_, base),
						offset: offset
					};

					tagged Lui { rd: .rd, imm: .imm }: return tagged Lui {
						rd: rd,
						imm: imm
					};

					tagged Store { op: .op, base: .base, value: .value, offset: .offset }: return tagged Store {
						op: op,
						base: fetch_x_reg(x_regs_, base),
						value: fetch_x_reg(x_regs_, value),
						offset: offset
					};
				endcase;

				let next_pc = pc + 4;

				case (alu.execute(pc, next_pc, ready_inst)) matches
					tagged Efault: state <= tagged Efault;

					tagged Sigill: state <= tagged Sigill;

					tagged Ok (ExecuteResultOk {
						x_regs_rd: .x_regs_rd,
						x_regs_rd_value: .x_regs_rd_value,
						jump_pc: .jump_pc
					}): begin
						if (x_regs_rd != 0)
							x_regs[x_regs_rd] <= x_regs_rd_value;

						case (jump_pc) matches
							tagged Invalid: pc <= next_pc;
							tagged Valid .jump_pc: pc <= jump_pc;
						endcase
					end
				endcase
			end
		endcase
	endmethod

	method InspectResult inspect;
		return InspectResult {
			state: state,
			pc: pc,
			x_regs: readVReg(x_regs)
		};
	endmethod
endmodule

function Maybe#(Instruction#(Either#(XReg, Int#(32)))) decode(RvDecoder decoder, Bit#(32) in);
	case (decoder.decode(in)) matches
		tagged Invalid: return tagged Invalid;

		tagged Valid .inst_decoded: return tagged Valid inst_decoded;
	endcase
endfunction

function Int#(32) fetch_x_reg(Vector#(32, Int#(32)) x_regs, Either#(XReg, Int#(32)) rs);
	case (rs) matches
		tagged Left .rs: return x_regs[rs];
		tagged Right .rs: return rs;
	endcase
endfunction
