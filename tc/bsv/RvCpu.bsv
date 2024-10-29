import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;
import Vector::*;

import RvAlu::*;
import RvCommon::*;
import RvDecoder::*;
import RvDecompressor::*;

typedef Server#(RvCpuRequest, RvCpuResponse) RvCpu;

typedef struct {
	Int#(64) csr_time;
	Bit#(32) in;
} RvCpuRequest deriving(Bits);

typedef struct {
	State state;
	Int#(64) pc;
	Int#(64) csr_cycle;
	Int#(64) csr_instret;
} RvCpuResponse deriving(Bits);

typedef union tagged {
	void Running;
	void Sigill;
	void Efault;
} State deriving(Bits);

(* synthesize *)
module mkRvCpu(RvCpu);
	Reg#(State) decoder_state <- mkReg(tagged Running);
	Reg#(State) decompressor_state <- mkReg(tagged Running);
	Reg#(State) execute_state <- mkReg(tagged Running);
	Reg#(Int#(63)) pc_hi <- mkReg(0);
	Vector#(32, Reg#(Int#(64))) x_regs <- replicateM(mkReg(0));
	Reg#(Int#(64)) csr_cycle <- mkReg(0);
	Reg#(Int#(64)) csr_instret <- mkReg(0);
	Wire#(InstructionLength) inst_len <- mkWire;

	RvDecompressor decompressor <- mkRvDecompressor(True);

	RvDecoder decoder <- mkRvDecoder;

	RvAlu alu <- mkRvAlu;

	FIFO#(RvCpuRequest) args_ <- mkBypassFIFO;
	GetS#(RvCpuRequest) args = fifoToGetS(args_);

	rule csr_cycle_increment;
		csr_cycle <= csr_cycle + 1;
	endrule

	rule fetch(args.first matches RvCpuRequest { in: .in });
		decompressor.request.put(RvDecompressorRequest { in: in });
	endrule

	rule decompress(decompressor_state matches Running);
		match RvDecompressorResponse { inst: .inst } = decompressor.response.first;
		case (inst) matches
			tagged Invalid: decompressor_state <= tagged Sigill;
			tagged Valid (tagged Compressed .inst): begin
				inst_len <= tagged Two;
				decoder.request.put(RvDecoderRequest { in: inst });
			end
			tagged Valid (tagged Uncompressed .inst): begin
				inst_len <= tagged Four;
				decoder.request.put(RvDecoderRequest { in: inst });
			end
		endcase
	endrule

	rule decode(decoder_state matches Running);
		match RvDecoderResponse { inst: .decoded_inst_ } = decoder.response.first;
		case (decoded_inst_) matches
			tagged Invalid: decoder_state <= tagged Sigill;

			tagged Valid .inst: begin
				Instruction#(Int#(64), Int#(64), Int#(64)) ready_inst = case (inst) matches
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
							csrs: rd == 0 ? ? : load_csr(csr_cycle, csr_instret, args.first.csr_time, csrs),
							rs2: load_x_reg(x_regs, rs2)
						};
						Csrrs: return tagged Csr {
							op: Csrrs,
							rd: rd,
							csrd: csrd,
							csrs: csrd == 0 ? ? : load_csr(csr_cycle, csr_instret, args.first.csr_time, csrs),
							rs2: load_x_reg(x_regs, rs2)
						};
						Csrrc: return tagged Csr {
							op: Csrrc,
							rd: rd,
							csrd: csrd,
							csrs: csrd == 0 ? ? : load_csr(csr_cycle, csr_instret, args.first.csr_time, csrs),
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

					tagged Unary { op: .op, rd: .rd, rs: .rs }: return tagged Unary {
						op: op,
						rd: rd,
						rs: x_regs[rs]
					};
				endcase;

				let next_pc = case (inst_len) matches
					tagged Two: return (zeroExtend(pc_hi) * 2) + 2;
					tagged Four: return (zeroExtend(pc_hi) * 2) + 4;
				endcase;

				alu.request.put(AluRequest {
					pc: zeroExtend(pc_hi) * 4,
					next_pc: next_pc,
					inst: ready_inst
				});
			end
		endcase
	endrule

	rule execute(execute_state matches Running);
		let alu_response = alu.response.first;
		case (alu_response) matches
			tagged Efault: execute_state <= tagged Efault;

			tagged Sigill: execute_state <= tagged Sigill;

			tagged Ok (AluResponseOk {
				x_regs_rd: .x_regs_rd,
				x_regs_rd_value: .x_regs_rd_value,
				csrd: .csrd,
				next_pc: .next_pc
			}): begin
				if (x_regs_rd != 0)
					x_regs[x_regs_rd] <= x_regs_rd_value;

				State next_execute_state = execute_state;

				if (csrd matches tagged Valid { .csrd, .csrd_value }) begin
					case (csrd) matches
						default: next_execute_state = tagged Efault;
					endcase
				end

				if (next_pc % 2 != 0)
					next_execute_state = tagged Efault;

				if (next_execute_state matches tagged Running)
					pc_hi <= truncate(next_pc / 2);

				execute_state <= next_execute_state;
			end
		endcase

		csr_instret <= csr_instret + 1;
	endrule

	interface request = toPut(args_);

	interface GetS response;
		method RvCpuResponse first;
			return RvCpuResponse {
				state: case (decompressor_state) matches
					tagged Running: case (decoder_state) matches
						tagged Running: return execute_state;
						.decoder_state: return decoder_state;
					endcase
					.decompressor_state: return decompressor_state;
				endcase,
				pc: zeroExtend(pc_hi) * 2,
				csr_cycle: csr_cycle,
				csr_instret: csr_instret
			};
		endmethod

		method Action deq;
			args_.deq;
			decompressor.response.deq;
			decoder.response.deq;
			alu.response.deq;
		endmethod
	endinterface
endmodule

typedef enum {
	Two,
	Four
} InstructionLength deriving(Bits);

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
			1'b1, // B
			1'b0  // A
		});
		12'hc00: return csr_cycle;
		12'hc01: return csr_time;
		12'hc02: return csr_instret;
		default: return 0;
	endcase
endfunction
