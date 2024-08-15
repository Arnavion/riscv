import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import Common::*;
import RvCommon::*;
import RvDecompressorCommon::*;

(* synthesize *)
module mkRvDecompressor(RvDecompressor);
	FIFO#(RvDecompressorRequest) args_ <- mkBypassFIFO;
	GetS#(RvDecompressorRequest) args = fifoToGetS(args_);
	FIFO#(RvDecompressorResponse) result_ <- mkBypassFIFO;
	Put#(RvDecompressorResponse) result = toPut(result_);

	rule run(args.first matches RvDecompressorRequest { in: .in });
		let inst = case (decompress(in)) matches
			tagged Invalid: return tagged Invalid;
			tagged Valid { .inst }: return tagged Valid (in[1:0] == 2'b11 ? tagged Uncompressed ({ inst, 2'b11 }) : tagged Compressed ({ inst, 2'b11 }));
		endcase;
		result.put(RvDecompressorResponse { inst: inst });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Maybe#(Bit#(30)) decompress(Bit#(32) in);
	case (in[1:0]) matches
		2'b00: case (in[15:13]) matches
			// addi4spn
			3'b000 &&& unpack(| in[12:2]): return tagged Valid
				type_i(OpCode_OpImm, { 2'b01, in[4:2] }, 3'b000, 5'b00010, zeroExtend({ in[10:7], in[12:11], in[5], in[6], 2'b00 }));

			// fld, lw, flw
			3'b0?? &&& unpack(| in[14:13]): return tagged Valid
				type_i(
					opcode_load(in[13]),
					{ 2'b01, in[4:2] },
					{ 2'b01, ~in[14] },
					{ 2'b01, in[9:7] },
					zeroExtend({ ~in[14] & in[6], in[5], in[12:10], in[14] & in[6], 2'b00 })
				);

			// fsd, sw, fsw
			3'b1?? &&& unpack(| in[14:13]): return tagged Valid
				type_s(
					opcode_store(in[13]),
					{ 2'b01, ~in[14] },
					{ 2'b01, in[9:7] },
					{ 2'b01, in[4:2] },
					zeroExtend({ ~in[14] & in[6], in[5], in[12:10], in[14] & in[6], 2'b00 })
				);

			default: return tagged Invalid;
		endcase

		2'b01: case (in[15:13]) matches
			// addi, li
			3'b0?0: return tagged Valid
				type_i(OpCode_OpImm, in[11:7], 3'b000, signExtend(~in[14]) & in[11:7], signExtend({ in[12], in[6:2] }));

			// jal, j
			3'b?01: return tagged Valid
				type_j(OpCode_Jal, { 4'b0000, ~in[15] }, signExtend({ in[12], in[8], in[10:9], in[6], in[7], in[2], in[11], in[5:3] }));

			3'b011: if (in[11:7] == 5'b00010)
				// addi16sp
				return tagged Valid
					type_i(OpCode_OpImm, in[11:7], 3'b000, in[11:7], signExtend({ in[12], in[4:3], in[5], in[2], in[6], 4'b0000 }));
			else
				// lui
				return tagged Valid
					type_u(OpCode_Lui, in[11:7], signExtend({ in[12], in[6:2] }));

			3'b100: case (in[11:10]) matches
				// srli, srai
				2'b0?: return tagged Valid
					type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b101, { 2'b01, in[9:7] }, { 1'b0, in[10], 4'b0000, in[12], in[6:2] });

				// andi
				2'b10: return tagged Valid
					type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b111, { 2'b01, in[9:7] }, signExtend({ in[12], in[6:2] }));

				2'b11: case (in[12]) matches
					// sub, xor, or, and
					1'b0: return tagged Valid
						type_r(OpCode_Op, { 2'b01, in[9:7] }, { | in[6:5], in[6], & in[6:5] }, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, { 1'b0, ~| in[6:5], 5'b00000 });

					default: return tagged Invalid;
				endcase
			endcase

			// beqz, bnez
			3'b11?: return tagged Valid
				type_b(OpCode_Branch, { 2'b00, in[13] }, { 2'b01, in[9:7] }, 5'b00000, signExtend({ in[12], in[6:5], in[2], in[11:10], in[4:3] }));
		endcase

		2'b10: case (in[15:13]) matches
			// slli
			3'b000: return tagged Valid
				type_i(OpCode_OpImm, in[11:7], 3'b001, in[11:7], { 6'b000000, in[12], in[6:2] });

			// fldsp, lwsp, flwsp
			3'b0?? &&& unpack(| in[14:13]): return tagged Valid
				type_i(
					opcode_load(in[13]),
					in[11:7],
					{ 2'b01, ~in[14] },
					5'b00010,
					zeroExtend({ ~in[14] & in[4], in[3:2], in[12], in[6:5], in[14] & in[4], 2'b00 })
				);

			3'b100: case ({ | in[11:7], | in[6:2] }) matches
				2'b00: if (unpack(in[12]))
					// ebreak
					return tagged Valid
						type_r(OpCode_System, 5'b00000, 3'b000, 5'b00000, 5'b00001, 7'b0000000);
				else return tagged Invalid;

				// jr, jalr
				2'b10: return tagged Valid
					type_i(OpCode_Jalr, { 4'b0000, in[12] }, 3'b000, in[11:7], '0);

				// mv, add
				2'b11: return tagged Valid
					type_r(OpCode_Op, in[11:7], 3'b000, signExtend(in[12]) & in[11:7], in[6:2], 7'b0000000);

				default: return tagged Invalid;
			endcase

			// fsdsp, swsp, fswsp
			3'b1?? &&& unpack(| in[14:13]): return tagged Valid
				type_s(
					opcode_store(in[13]),
					{ 2'b01, ~in[14] },
					5'b00010,
					in[6:2],
					zeroExtend({ ~in[14] & in[9], in[8:7], in[12:10], in[14] & in[9], 2'b00 })
				);
		endcase

		// uncompressed
		2'b11: return tagged Valid in[31:2];
	endcase
endfunction

`ifdef TESTING
import StmtFSM::*;
import Vector::*;

(* synthesize *)
module mkTest();
	let decompressor <- mkRvDecompressor;
	let m <- mkTestDecompressorModule(decompressor);
	return m;
endmodule
`endif
