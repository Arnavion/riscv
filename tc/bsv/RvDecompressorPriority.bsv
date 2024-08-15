import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import Common::*;
import RvCommon::*;
import RvDecompressorCommon::*;

(* synthesize *)
(* descending_urgency = "addi16sp, lui" *)
(* descending_urgency = "ebreak, jr_jalr" *)
(* descending_urgency = "ebreak, mv_add" *)
(* descending_urgency = "jr_jalr, mv_add" *)
(* descending_urgency = "addi4spn, invalid" *)
(* descending_urgency = "fld_lw_flw, invalid" *)
(* descending_urgency = "fsd_sw_fsw, invalid" *)
(* descending_urgency = "addi_li, invalid" *)
(* descending_urgency = "jal_j, invalid" *)
(* descending_urgency = "addi16sp, invalid" *)
(* descending_urgency = "lui, invalid" *)
(* descending_urgency = "srli_srai, invalid" *)
(* descending_urgency = "andi, invalid" *)
(* descending_urgency = "sub_xor_or_and, invalid" *)
(* descending_urgency = "beqz_bnez, invalid" *)
(* descending_urgency = "slli, invalid" *)
(* descending_urgency = "fldsp_lwsp_flwsp, invalid" *)
(* descending_urgency = "ebreak, invalid" *)
(* descending_urgency = "jr_jalr, invalid" *)
(* descending_urgency = "mv_add, invalid" *)
(* descending_urgency = "fsdsp_swsp_fswsp, invalid" *)
(* descending_urgency = "uncompressed, invalid" *)
module mkRvDecompressorPriority(RvDecompressor);
	FIFO#(RvDecompressorRequest) args_ <- mkBypassFIFO;
	GetS#(RvDecompressorRequest) args = fifoToGetS(args_);
	FIFO#(RvDecompressorResponse) result_ <- mkBypassFIFO;
	Put#(RvDecompressorResponse) result = toPut(result_);

	rule addi4spn(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b000_????????_???_00 &&& unpack(| in[12:2]));
		write_out(in, result, type_i(
			OpCode_OpImm,
			{ 2'b01, in[4:2] },
			3'b000,
			5'b00010,
			zeroExtend({ in[10:7], in[12:11], in[5], in[6], 2'b00 })
		));
	endrule

	rule fld_lw_flw(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b0??_???_???_??_???_00 &&& unpack(| in[14:13]));
		write_out(in, result, type_i(
			opcode_load(in[13]),
			{ 2'b01, in[4:2] },
			{ 2'b01, ~in[14] },
			{ 2'b01, in[9:7] },
			zeroExtend({ ~in[14] & in[6], in[5], in[12:10], in[14] & in[6], 2'b00 })
		));
	endrule

	rule fsd_sw_fsw(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b1??_???_???_??_???_00 &&& unpack(| in[14:13]));
		write_out(in, result, type_s(
			opcode_store(in[13]),
			{ 2'b01, ~in[14] },
			{ 2'b01, in[9:7] },
			{ 2'b01, in[4:2] },
			zeroExtend({ ~in[14] & in[6], in[5], in[12:10], in[14] & in[6], 2'b00 })
		));
	endrule

	rule addi_li(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b0?0_?_?????_?????_01);
		write_out(in, result, type_i(
			OpCode_OpImm,
			in[11:7],
			3'b000,
			signExtend(~in[14]) & in[11:7],
			signExtend({ in[12], in[6:2] })
		));
	endrule

	rule jal_j(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b?01_???????????_01);
		write_out(in, result, type_j(
			OpCode_Jal,
			{ 4'b0000, ~in[15] },
			signExtend({ in[12], in[8], in[10:9], in[6], in[7], in[2], in[11], in[5:3] })
		));
	endrule

	rule addi16sp(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b011_?_00010_?????_01);
		write_out(in, result, type_i(
			OpCode_OpImm,
			in[11:7],
			3'b000,
			in[11:7],
			signExtend({ in[12], in[4:3], in[5], in[2], in[6], 4'b0000 })
		));
	endrule

	rule lui(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b011_?_?????_?????_01);
		write_out(in, result, type_u(
			OpCode_Lui,
			in[11:7],
			signExtend({ in[12], in[6:2] })
		));
	endrule

	rule srli_srai(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b100_?_0?_???_?????_01);
		write_out(in, result, type_i(
			OpCode_OpImm,
			{ 2'b01, in[9:7] },
			3'b101,
			{ 2'b01, in[9:7] },
			{ 1'b0, in[10], 4'b0000, in[12], in[6:2] }
		));
	endrule

	rule andi(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b100_?_10_???_?????_01);
		write_out(in, result, type_i(
			OpCode_OpImm,
			{ 2'b01, in[9:7] },
			3'b111,
			{ 2'b01, in[9:7] },
			signExtend({ in[12], in[6:2] })
		));
	endrule

	rule sub_xor_or_and(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b100_011_???_??_???_01);
		write_out(in, result, type_r(
			OpCode_Op,
			{ 2'b01, in[9:7] },
			{ | in[6:5], in[6], & in[6:5] },
			{ 2'b01, in[9:7] },
			{ 2'b01, in[4:2] },
			{ 1'b0, ~| in[6:5], 5'b00000 }
		));
	endrule

	rule beqz_bnez(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b11?_?_?????_?????_01);
		write_out(in, result, type_b(
			OpCode_Branch,
			{ 2'b00, in[13] },
			{ 2'b01, in[9:7] },
			5'b00000,
			signExtend({ in[12], in[6:5], in[2], in[11:10], in[4:3] })
		));
	endrule

	rule slli(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b000_?_?????_?????_10);
		write_out(in, result, type_i(
			OpCode_OpImm,
			in[11:7],
			3'b001,
			in[11:7],
			{ 6'b000000, in[12], in[6:2] }
		));
	endrule

	rule fldsp_lwsp_flwsp(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b0??_?_?????_?????_10 &&& unpack(| in[14:13]));
		write_out(in, result, type_i(
			opcode_load(in[13]),
			in[11:7],
			{ 2'b01, ~in[14] },
			5'b00010,
			zeroExtend({ ~in[14] & in[4], in[3:2], in[12], in[6:5], in[14] & in[4], 2'b00 })
		));
	endrule

	rule ebreak(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b100_1_00000_00000_10);
		write_out(in, result, type_r(
			OpCode_System,
			5'b00000,
			3'b000,
			5'b00000,
			5'b00001,
			7'b0000000
		));
	endrule

	rule jr_jalr(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b100_?_?????_00000_10);
		write_out(in, result, type_i(
			OpCode_Jalr,
			{ 4'b0000, in[12] },
			3'b000,
			in[11:7],
			'0
		));
	endrule

	rule mv_add(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b100_?_?????_?????_10);
		write_out(in, result, type_r(
			OpCode_Op,
			in[11:7],
			3'b000,
			signExtend(in[12]) & in[11:7],
			in[6:2],
			7'b0000000
		));
	endrule

	rule fsdsp_swsp_fswsp(args.first matches RvDecompressorRequest { in: .in } &&& in[15:0] matches 16'b1??_??????_?????_10 &&& unpack(| in[14:13]));
		write_out(in, result, type_s(
			opcode_store(in[13]),
			{ 2'b01, ~in[14] },
			5'b00010,
			in[6:2],
			zeroExtend({ ~in[14] & in[9], in[8:7], in[12:10], in[14] & in[9], 2'b00 })
		));
	endrule

	rule uncompressed(args.first matches RvDecompressorRequest { in: .in } &&& in[1:0] == 2'b11);
		write_out(in, result, in[31:2]);
	endrule

	rule invalid(args.first matches RvDecompressorRequest { in: .in });
		// TODO: Load-bearing log. Removing this makes `make test-decompressor_priority-bsv` fail.
		// The visualization of the SV works correctly regardless. bsim bug?
		$display("%h", in);

		result.put(RvDecompressorResponse {
			inst: tagged Invalid
		});
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Action write_out(Bit#(32) in, Put#(RvDecompressorResponse) result, Bit#(30) inst) =
	result.put(RvDecompressorResponse {
		inst: tagged Valid (unpack(& in[1:0]) ?
			tagged Uncompressed ({ inst, 2'b11 }) :
			tagged Compressed ({ inst, 2'b11 })
		)
	});

`ifdef TESTING
import StmtFSM::*;
import Vector::*;

(* synthesize *)
module mkTest();
	let decompressor <- mkRvDecompressorPriority;
	let m <- mkTestDecompressorModule(decompressor);
	return m;
endmodule
`endif
