import ClientServer::*;
import GetPut::*;
import Vector::*;

import RvAlu::*;
import RvCommon::*;
import RvDecoder::*;
import RvDecompressor::*;

typedef Server#(RvCpuRequest, RvCpuResponse) RvCpu;

typedef struct {
	Bit#(32) in;
} RvCpuRequest deriving(Bits);

typedef struct {
	State state;
	Int#(32) pc;
	Vector#(32, Int#(32)) x_regs;
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
	Reg#(Int#(31)) pc_hi <- mkReg(0);
	Vector#(32, Reg#(Int#(32))) x_regs <- replicateM(mkReg(0));

	Wire#(Bit#(32)) in <- mkWire;

	RvDecompressor decompressor <- mkRvDecompressor;

	Wire#(InstructionLength) inst_len <- mkWire;

	RvDecoder decoder <- mkRvDecoder;

	Wire#(Instruction#(XReg, Either#(XReg, Int#(12)))) loader <- mkWire;

	RvAlu alu <- mkRvAlu;

	rule fetch;
		decompressor.request.put(RvDecompressorRequest { in: in });
	endrule

	rule decompress(decompressor_state matches Running);
		let decompressor_response <- decompressor.response.get;
		case (decompressor_response.inst) matches
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
		let decode_response <- decoder.response.get;
		case (decode_response.inst) matches
			tagged Invalid: decoder_state <= tagged Sigill;
			tagged Valid .inst: loader <= inst;
		endcase
	endrule

	rule load;
		let inst = loader;

		Instruction#(Int#(32), Int#(32)) ready_inst = case (inst) matches
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

			tagged Branch { op: .op, rs1: .rs1, rs2: .rs2, imm: .imm }: return tagged Branch {
				op: op,
				rs1: x_regs[rs1],
				rs2: load_x_reg(x_regs, rs2),
				imm: imm
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
		endcase;

		let next_pc = case (inst_len) matches
			tagged Two: return (zeroExtend(pc_hi) * 2) + 2;
			tagged Four: return (zeroExtend(pc_hi) * 2) + 4;
		endcase;

		alu.request.put(AluRequest {
			pc: zeroExtend(pc_hi) * 2,
			next_pc: next_pc,
			inst: ready_inst
		});
	endrule

	rule execute(execute_state matches Running);
		let alu_response <- alu.response.get;
		case (alu_response) matches
			tagged Efault: execute_state <= tagged Efault;

			tagged Sigill: execute_state <= tagged Sigill;

			tagged Ok (AluResponseOk {
				x_regs_rd: .x_regs_rd,
				x_regs_rd_value: .x_regs_rd_value,
				next_pc: .next_pc
			}): begin
				if (x_regs_rd != 0)
					x_regs[x_regs_rd] <= x_regs_rd_value;

				if (next_pc % 2 == 0)
					pc_hi <= truncate(next_pc / 2);
				else
					execute_state <= tagged Efault;
			end
		endcase
	endrule

	interface Put request;
		method Action put(RvCpuRequest request);
			in <= request.in;
		endmethod
	endinterface

	interface Get response;
		method ActionValue#(RvCpuResponse) get;
			return RvCpuResponse {
				state: case (decompressor_state) matches
					tagged Running: case (decoder_state) matches
						tagged Running: return execute_state;
						.decoder_state: return decoder_state;
					endcase
					.decompressor_state: return decompressor_state;
				endcase,
				pc: zeroExtend(pc_hi) * 2,
				x_regs: readVReg(x_regs)
			};
		endmethod
	endinterface
endmodule

typedef enum {
	Two,
	Four
} InstructionLength deriving(Bits);

function Int#(32) load_x_reg(Vector#(32, Reg#(Int#(32))) x_regs, Either#(XReg, Int#(12)) rs);
	case (rs) matches
		tagged Left .rs: return x_regs[rs];
		tagged Right .imm: return extend(imm);
	endcase
endfunction
