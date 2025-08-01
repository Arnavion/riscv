import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;
import Vector::*;

import Common::*;
import RvAlu::*;
import RvCommon::*;
import RvDecoder::*;
import RvDecompressor::*;
import RvDecompressorCommon::*;
import RvRegisters::*;

typedef Server#(RvCpuRequest, RvCpuResponse) RvCpu;

typedef struct {
	Int#(64) csr_time;
	Bit#(32) in;
} RvCpuRequest deriving(Bits);

typedef struct {
	State state;
	Int#(64) pc;
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
	Wire#(InstructionLength) inst_len <- mkWire;

	RvRegisters registers <- mkRvRegisters;

	RvDecompressor decompressor <- mkRvDecompressor(True);

	RvDecoder decoder <- mkRvDecoder;

	RvAlu alu <- mkRvAlu;

	FIFO#(RvCpuRequest) args_ <- mkBypassFIFO;
	GetS#(RvCpuRequest) args = fifoToGetS(args_);

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
				let ready_inst = registers.load(inst, args.first.csr_time);

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
				State next_execute_state = execute_state;

				let faulted <- registers.store(x_regs_rd, x_regs_rd_value, csrd);
				if (faulted)
					next_execute_state = tagged Efault;

				if (next_pc % 2 != 0)
					next_execute_state = tagged Efault;

				if (next_execute_state matches tagged Running)
					pc_hi <= truncate(next_pc / 2);

				execute_state <= next_execute_state;
			end
		endcase
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
				pc: zeroExtend(pc_hi) * 2
			};
		endmethod

		method Action deq;
			args_.deq;
			decompressor.response.deq;
			decoder.response.deq;
			alu.response.deq;
			registers.retire(1);
		endmethod
	endinterface
endmodule

typedef enum {
	Two,
	Four
} InstructionLength deriving(Bits);
