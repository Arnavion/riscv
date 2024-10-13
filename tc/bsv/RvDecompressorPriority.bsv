import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import RvCommon::*;
import RvDecompressor::*;

(* synthesize *)
(* descending_urgency = "addi16sp, lui" *)
(* descending_urgency = "ebreak, mv_add" *)
(* descending_urgency = "jr_jalr, mv_add" *)
module mkRvDecompressorPriority#(parameter Bool rv64)(RvDecompressor);
	Wire#(Bit#(32)) in <- mkWire;
	Wire#(Bit#(30)) out <- mkWire;

	FIFO#(RvDecompressorRequest) args_ <- mkBypassFIFO;
	GetS#(RvDecompressorRequest) args = fifoToGetS(args_);
	FIFO#(RvDecompressorResponse) result_ <- mkBypassFIFO;
	Put#(RvDecompressorResponse) result = toPut(result_);

	rule prepare_args;
		in <= args.first.in;
	endrule

	rule prepare_result;
		result.put(RvDecompressorResponse {
			inst: tagged Valid (
				unpack(& in[1:0]) ?
					tagged Uncompressed ({ out, 2'b11 }) :
					tagged Compressed ({ out, 2'b11 })
			)
		});
	endrule

	rule addi4spn(in[15:0] matches 16'b000_????????_000_00 &&& unpack(| in[12:5]));
		out <= type_i_(
			OpCode_OpImm,
			{ 2'b01, in[4:2] },
			3'b000,
			5'b00010,
			zeroExtend({ in[10:7], in[12:11], in[5], in[6], 2'b00 })
		);
	endrule

	rule fld_ld_lw_flw(in[15:0] matches 16'b0??_???_???_??_???_00 &&& unpack(| in[14:13]));
		out <= type_i_(
			opcode_load(rv64 ? ~in[14] : in[13]),
			{ 2'b01, in[4:2] },
			{ 2'b01, rv64 ? in[13] : ~in[14] },
			{ 2'b01, in[9:7] },
			zeroExtend({ (rv64 ? in[13] : ~in[14]) & in[6], in[5], in[12:10], (rv64 ? ~in[13] : in[14]) & in[6], 2'b00 })
		);
	endrule

	rule lbu_lhu_lh(in[15:0] matches 16'b100_00?_???_??_???_00);
		out <= type_i_(
			OpCode_Load,
			{ 2'b01, in[4:2] },
			{ ~in[10] | ~in[6], 1'b0, in[10] },
			{ 2'b01, in[9:7] },
			zeroExtend({ in[5], ~in[10] & in[6] })
		);
	endrule

	rule sb_sh(in[15:0] matches 16'b100_010_???_??_???_00);
		out <= type_s_(
			OpCode_Store,
			{ 2'b00, in[10] },
			{ 2'b01, in[9:7] },
			{ 2'b01, in[4:2] },
			zeroExtend({ in[5], ~in[10] & in[6] })
		);
	endrule

	rule fsd_sd_sw_fsw(in[15:0] matches 16'b1??_???_???_??_???_00 &&& unpack(| in[14:13]));
		out <= type_s_(
			opcode_store(rv64 ? ~in[14] : in[13]),
			{ 2'b01, rv64 ? in[13] : ~in[14] },
			{ 2'b01, in[9:7] },
			{ 2'b01, in[4:2] },
			zeroExtend({ (rv64 ? in[13] : ~in[14]) & in[6], in[5], in[12:10], (rv64 ? ~in[13] : in[14]) & in[6], 2'b00 })
		);
	endrule

	rule addi_addiw_li(rv64 &&& in[15:0] matches 16'b0??_?_?????_?????_01 &&& unpack(~& in[14:13]));
		out <= type_i_(
			opcode_opimm(in[13]),
			in[11:7],
			3'b000,
			signExtend(~in[14]) & in[11:7],
			signExtend({ in[12], in[6:2] })
		);
	endrule

	rule addi_li(!rv64 &&& in[15:0] matches 16'b0?0_?_?????_?????_01);
		out <= type_i_(
			OpCode_OpImm,
			in[11:7],
			3'b000,
			signExtend(~in[14]) & in[11:7],
			signExtend({ in[12], in[6:2] })
		);
	endrule

	rule jal_j(!rv64 &&& in[15:0] matches 16'b?01_???????????_01);
		out <= type_j_(
			OpCode_Jal,
			{ 4'b0000, ~in[15] },
			signExtend({ in[12], in[8], in[10:9], in[6], in[7], in[2], in[11], in[5:3] })
		);
	endrule

	rule addi16sp(in[15:0] matches 16'b011_?_00010_?????_01);
		out <= type_i_(
			OpCode_OpImm,
			in[11:7],
			3'b000,
			in[11:7],
			signExtend({ in[12], in[4:3], in[5], in[2], in[6], 4'b0000 })
		);
	endrule

	rule lui(in[15:0] matches 16'b011_?_?????_?????_01);
		out <= type_u_(
			OpCode_Lui,
			in[11:7],
			signExtend({ in[12], in[6:2] })
		);
	endrule

	rule srli_srai(in[15:0] matches 16'b100_?_0?_???_?????_01);
		out <= type_i_(
			OpCode_OpImm,
			{ 2'b01, in[9:7] },
			3'b101,
			{ 2'b01, in[9:7] },
			{ 1'b0, in[10], 4'b0000, in[12], in[6:2] }
		);
	endrule

	rule andi(in[15:0] matches 16'b100_?_10_???_?????_01);
		out <= type_i_(
			OpCode_OpImm,
			{ 2'b01, in[9:7] },
			3'b111,
			{ 2'b01, in[9:7] },
			signExtend({ in[12], in[6:2] })
		);
	endrule

	rule sub_xor_or_and(in[15:0] matches 16'b100_011_???_??_???_01);
		out <= type_r_(
			OpCode_Op,
			{ 2'b01, in[9:7] },
			{ | in[6:5], in[6], & in[6:5] },
			{ 2'b01, in[9:7] },
			{ 2'b01, in[4:2] },
			{ 1'b0, ~| in[6:5], 5'b00000 }
		);
	endrule

	rule subw_addw(rv64 &&& in[15:0] matches 16'b100_111_???_0?_???_01);
		out <= type_r_(
			OpCode_Op32,
			{ 2'b01, in[9:7] },
			3'b000,
			{ 2'b01, in[9:7] },
			{ 2'b01, in[4:2] },
			{ 1'b0, ~in[5], 5'b00000 }
		);
	endrule

	rule zext_b(in[15:0] matches 16'b100_111_???_11_000_01);
		out <= type_i_(
			OpCode_OpImm,
			{ 2'b01, in[9:7] },
			3'b111,
			{ 2'b01, in[9:7] },
			12'b000011111111
		);
	endrule

	rule zext_w(rv64 &&& in[15:0] matches 16'b100_111_???_11_100_01);
		out <= type_r_(
			OpCode_Op32,
			{ 2'b01, in[9:7] },
			3'b000,
			{ 2'b01, in[9:7] },
			5'b00000,
			7'b0000100
		);
	endrule

	rule not_(in[15:0] matches 16'b100_111_???_11_101_01);
		out <= type_i_(
			OpCode_OpImm,
			{ 2'b01, in[9:7] },
			3'b100,
			{ 2'b01, in[9:7] },
			12'b111111111111
		);
	endrule

	rule j(rv64 &&& in[15:0] matches 16'b101_???????????_01);
		out <= type_j_(
			OpCode_Jal,
			5'b00000,
			signExtend({ in[12], in[8], in[10:9], in[6], in[7], in[2], in[11], in[5:3] })
		);
	endrule

	rule beqz_bnez(in[15:0] matches 16'b11?_?_?????_?????_01);
		out <= type_b_(
			OpCode_Branch,
			{ 2'b00, in[13] },
			{ 2'b01, in[9:7] },
			5'b00000,
			signExtend({ in[12], in[6:5], in[2], in[11:10], in[4:3] })
		);
	endrule

	rule slli(in[15:0] matches 16'b000_?_?????_?????_10);
		out <= type_i_(
			OpCode_OpImm,
			in[11:7],
			3'b001,
			in[11:7],
			{ 6'b000000, in[12], in[6:2] }
		);
	endrule

	rule fldsp_ldsp_lwsp_flwsp(in[15:0] matches 16'b0??_?_?????_?????_10 &&& unpack(| in[14:13]));
		out <= type_i_(
			opcode_load(rv64 ? ~in[14] : in[13]),
			in[11:7],
			{ 2'b01, rv64 ? in[13] : ~in[14] },
			5'b00010,
			zeroExtend({ (rv64 ? in[13] : ~in[14]) & in[4], in[3:2], in[12], in[6:5], (rv64 ? ~in[13] : in[14]) & in[4], 2'b00 })
		);
	endrule

	rule ebreak(in[15:0] matches 16'b100_1_00000_00000_10);
		out <= type_r_(
			OpCode_System,
			5'b00000,
			3'b000,
			5'b00000,
			5'b00001,
			7'b0000000
		);
	endrule

	rule jr_jalr(in[15:0] matches 16'b100_0_?????_00000_10);
		out <= type_i_(
			OpCode_Jalr,
			{ 4'b0000, in[12] },
			3'b000,
			in[11:7],
			'0
		);
	endrule

	rule mv_add(in[15:0] matches 16'b100_?_?????_?????_10);
		out <= type_r_(
			OpCode_Op,
			in[11:7],
			3'b000,
			signExtend(in[12]) & in[11:7],
			in[6:2],
			7'b0000000
		);
	endrule

	rule fsdsp_sdsp_swsp_fswsp(in[15:0] matches 16'b1??_??????_?????_10 &&& unpack(| in[14:13]));
		out <= type_s_(
			opcode_store(rv64 ? ~in[14] : in[13]),
			{ 2'b01, rv64 ? in[13] : ~in[14] },
			5'b00010,
			in[6:2],
			zeroExtend({ (rv64 ? in[13] : ~in[14]) & in[9], in[8:7], in[12:10], (rv64 ? ~in[13] : in[14]) & in[9], 2'b00 })
		);
	endrule

	rule uncompressed(in[1:0] == 2'b11);
		out <= in[31:2];
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Bit#(30) type_r_(
	OpCode opcode,
	XReg rd,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(7) funct7
);
	return type_r(opcode, rd, funct3, rs1, rs2, funct7);
endfunction

function Bit#(30) type_i_(
	OpCode opcode,
	XReg rd,
	Bit#(3) funct3,
	XReg rs1,
	Bit#(12) imm
);
	return type_i(opcode, rd, funct3, rs1, imm);
endfunction

function Bit#(30) type_s_(
	OpCode opcode,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(12) imm
);
	return type_s(opcode, funct3, rs1, rs2, imm);
endfunction

function Bit#(30) type_b_(
	OpCode opcode,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(12) imm
);
	return type_b(opcode, funct3, rs1, rs2, imm);
endfunction

function Bit#(30) type_u_(
	OpCode opcode,
	XReg rd,
	Bit#(20) imm
);
	return type_u(opcode, rd, imm);
endfunction

function Bit#(30) type_j_(
	OpCode opcode,
	XReg rd,
	Bit#(20) imm
);
	return type_j(opcode, rd, imm);
endfunction
