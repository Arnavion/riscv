import Vector::*;

import RvAlu::*;
import RvCommon::*;
import RvDecoder::*;
import RvDecompressor::*;

interface RvCpu;
	method Action feed(Int#(64) csr_time, Bit#(32) in);
	method InspectResult inspect;
endinterface

typedef struct {
	State state;
	Int#(64) pc;
	Vector#(32, Int#(64)) x_regs;
	Int#(64) csr_cycle;
	Int#(64) csr_instret;
} InspectResult deriving(Bits);

typedef union tagged {
	void Running;
	void Sigill;
	void Efault;
} State deriving(Bits);

(* synthesize *)
module mkRvCpu(RvCpu);
	Reg#(State) state <- mkReg(tagged Running);
	Reg#(Int#(64)) pc <- mkReg(0);
	Vector#(32, Reg#(Int#(64))) x_regs <- replicateM(mkReg(0));

	Reg#(Int#(64)) csr_cycle <- mkReg(0);
	Reg#(Int#(64)) csr_instret <- mkReg(0);

	RvAlu alu <- mkRvAlu;
	RvDecoder decoder <- mkRvDecoder;
	RvDecompressor decompressor <- mkRvDecompressor(True);

	method Action feed(Int#(64) csr_time, Bit#(32) in) if (state matches Running);
		case (decode(decompressor, decoder, in)) matches
			tagged Invalid: state <= tagged Sigill;

			tagged Valid { .inst, .inst_len }: begin
				let x_regs_ = readVReg(x_regs);

				Instruction#(Int#(64), Csr, Int#(64)) ready_inst = case (inst) matches
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

					tagged Csr (tagged Csrr { rd: .rd, csrs: .csrs }): return tagged Csr tagged Csrr {
						rd: rd,
						csrs: fetch_csr(csr_cycle, csr_instret, csr_time, csrs)
					};
					tagged Csr (tagged Csrs { rs1: .rs1, csrd: .csrd }): return tagged Csr tagged Csrs {
						rs1: fetch_x_reg(x_regs_, rs1),
						csrd: csrd
					};
					tagged Csr (tagged Csrrw { rd: .rd, rs1: .rs1, csrd: .csrd, csrs: .csrs }): return tagged Csr tagged Csrrw {
						rd: rd,
						rs1: fetch_x_reg(x_regs_, rs1),
						csrd: csrd,
						csrs: fetch_csr(csr_cycle, csr_instret, csr_time, csrs)
					};
					tagged Csr (tagged Csrrs { rd: .rd, rs1: .rs1, csrd: .csrd, csrs: .csrs }): return tagged Csr tagged Csrrs {
						rd: rd,
						rs1: fetch_x_reg(x_regs_, rs1),
						csrd: csrd,
						csrs: fetch_csr(csr_cycle, csr_instret, csr_time, csrs)
					};
					tagged Csr (tagged Csrrc { rd: .rd, rs1: .rs1, csrd: .csrd, csrs: .csrs }): return tagged Csr tagged Csrrc {
						rd: rd,
						rs1: fetch_x_reg(x_regs_, rs1),
						csrd: csrd,
						csrs: fetch_csr(csr_cycle, csr_instret, csr_time, csrs)
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

					tagged Unary { op: .op, rd: .rd, rs: .rs }: return tagged Unary {
						op: op,
						rd: rd,
						rs: fetch_x_reg(x_regs_, rs)
					};
				endcase;

				let next_pc = case (inst_len) matches
					tagged Two: return pc + 2;
					tagged Four: return pc + 4;
				endcase;

				case (alu.execute(pc, next_pc, ready_inst)) matches
					tagged Efault: state <= tagged Efault;

					tagged Sigill: state <= tagged Sigill;

					tagged Ok (ExecuteResultOk {
						x_regs_rd: .x_regs_rd,
						x_regs_rd_value: .x_regs_rd_value,
						csrd: .csrd,
						jump_pc: .jump_pc
					}): begin
						if (x_regs_rd != 0)
							x_regs[x_regs_rd] <= x_regs_rd_value;

						if (csrd matches tagged Valid { .csrd, .csrd_value }) begin
							case (csrd) matches
								default: state <= tagged Efault;
							endcase
						end

						case (jump_pc) matches
							tagged Invalid: pc <= next_pc;
							tagged Valid .jump_pc: pc <= jump_pc;
						endcase
					end
				endcase

				csr_cycle <= csr_cycle + 1;
				csr_instret <= csr_instret + 1;
			end
		endcase
	endmethod

	method InspectResult inspect;
		return InspectResult {
			state: state,
			pc: pc,
			x_regs: readVReg(x_regs),
			csr_cycle: csr_cycle,
			csr_instret: csr_instret
		};
	endmethod
endmodule

typedef enum {
	Two,
	Four
} InstructionLength deriving(Bits);

function Maybe#(Tuple2#(Instruction#(Either#(XReg, Int#(64)), Csr, Csr), InstructionLength)) decode(RvDecompressor decompressor, RvDecoder decoder, Bit#(32) in);
	let inst_decompressed = decompressor.decompress(in);

	case (inst_decompressed) matches
		tagged Invalid: return tagged Invalid;

		tagged Valid .inst: begin
			match { .inst_decompressed, .inst_len } = case (inst) matches
				tagged Compressed .inst: return tuple2(inst, tagged Two);
				tagged Uncompressed .inst: return tuple2(inst, tagged Four);
			endcase;

			case (decoder.decode(inst_decompressed)) matches
				tagged Invalid: return tagged Invalid;

				tagged Valid .inst_decoded: return tagged Valid tuple2(inst_decoded, inst_len);
			endcase
		end
	endcase
endfunction

function Int#(64) fetch_x_reg(Vector#(32, Int#(64)) x_regs, Either#(XReg, Int#(64)) rs);
	case (rs) matches
		tagged Left .rs: return x_regs[rs];
		tagged Right .rs: return rs;
	endcase
endfunction

function Int#(64) fetch_csr(Reg#(Int#(64)) csr_cycle, Reg#(Int#(64)) csr_instret, Int#(64) csr_time, Csr csrs);
	case (csrs) matches
		12'hc00: return csr_cycle;
		12'hc01: return csr_time;
		12'hc02: return csr_instret;
		default: return 0;
	endcase
endfunction
