import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;
import Vector::*;

import Common::*;
import RvAlu::*;
import RvCommon::*;
import RvDecoder::*;
import RvRegisters::*;

typedef Server#(RvCpuRequest, RvCpuResponse) RvCpu;

typedef struct {
	Bit#(32) in;
} RvCpuRequest deriving(Bits);

typedef struct {
	State state;
	Int#(32) pc;
} RvCpuResponse deriving(Bits);

typedef union tagged {
	void Running;
	void Sigill;
	void Efault;
} State deriving(Bits);

(* synthesize *)
module mkRvCpu(RvCpu);
	Reg#(State) decoder_state <- mkReg(tagged Running);
	Reg#(State) execute_state <- mkReg(tagged Running);
	Reg#(Int#(30)) pc_hi <- mkReg(0);

	RvRegisters registers <- mkRvRegisters;

	RvDecoder decoder <- mkRvDecoder;

	RvAlu alu <- mkRvAlu;

	FIFO#(RvCpuRequest) args_ <- mkBypassFIFO;
	GetS#(RvCpuRequest) args = fifoToGetS(args_);

	rule fetch(args.first matches RvCpuRequest { in: .in });
		decoder.request.put(RvDecoderRequest { in: in });
	endrule

	rule decode(decoder_state matches Running);
		match RvDecoderResponse { inst: .decoded_inst_ } = decoder.response.first;
		case (decoded_inst_) matches
			tagged Invalid: decoder_state <= tagged Sigill;

			tagged Valid .inst: begin
				let ready_inst = registers.load(inst);

				let next_pc = (zeroExtend(pc_hi) * 4) + 4;

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
				next_pc: .next_pc
			}): begin
				registers.store(x_regs_rd, x_regs_rd_value);

				if (next_pc % 4 == 0)
					pc_hi <= truncate(next_pc / 4);
				else
					execute_state <= tagged Efault;
			end
		endcase
	endrule

	interface request = toPut(args_);

	interface GetS response;
		method RvCpuResponse first = RvCpuResponse {
			state: case (decoder_state) matches
				tagged Running: return execute_state;
				.decoder_state: return decoder_state;
			endcase,
			pc: zeroExtend(pc_hi) * 4
		};

		method Action deq;
			args_.deq;
			decoder.response.deq;
			alu.response.deq;
		endmethod
	endinterface
endmodule
