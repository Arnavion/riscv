import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import Common::*;
import RvCommon::*;

typedef Server#(RvDecoderRequest, RvDecoderResponse) RvDecoder;

typedef struct {
	Bit#(32) in;
} RvDecoderRequest deriving(Bits);

typedef struct {
	Maybe#(Instruction#(XReg, Either#(XReg, Int#(12)))) inst;
} RvDecoderResponse deriving(Bits);

(* synthesize *)
module mkRvDecoder(RvDecoder);
	FIFO#(RvDecoderRequest) args_ <- mkBypassFIFO;
	GetS#(RvDecoderRequest) args = fifoToGetS(args_);
	FIFO#(RvDecoderResponse) result_ <- mkBypassFIFO;
	Put#(RvDecoderResponse) result = toPut(result_);

	rule run(args.first matches RvDecoderRequest { in: .in });
		result.put(RvDecoderResponse { inst: decode(in) });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Maybe#(Instruction#(XReg, Either#(XReg, Int#(12)))) decode(Bit#(32) in);
	if (unpack(~& in[1:0]))
		return tagged Invalid;

	else begin
		OpCode opcode = unpack(in[6:2]);
		let funct3 = in[14:12];
		let funct7 = in[31:25];
		let rd = in[11:7];
		let rs1 = in[19:15];
		let rs2 = in[24:20];
		let csr = in[31:20];
		UInt#(5) csrimm = unpack(in[19:15]);

		Int#(12) i_imm = unpack(in[31:20]);
		Int#(32) s_imm = extend(unpack({ in[31:25], in[11:7] }));
		Int#(32) b_imm = extend(unpack({ in[31], in[7], in[30:25], in[11:8], 1'b0 }));
		Int#(32) u_imm = unpack({ in[31:12], 12'h000 });
		Int#(32) j_imm = extend(unpack({ in[31], in[19:12], in[20], in[30:21], 1'b0 }));

		case (opcode) matches
			OpCode_Load: case (parse_load_op(funct3)) matches
				tagged Invalid: return tagged Invalid;

				tagged Valid .op: return tagged Valid tagged Load { op: op, rd: rd, base: rs1, offset: extend(i_imm) };
			endcase

			OpCode_MiscMem: return tagged Valid Fence;

			OpCode_OpImm: case (funct3) matches
				3'b000: return tagged Valid tagged Binary { op: Add, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
				3'b001: case (pack(i_imm)[11:5]) matches
					7'b0000000: return tagged Valid tagged Binary { op: Sll, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
					default: return tagged Invalid;
				endcase
				3'b010: return tagged Valid tagged Binary { op: Slt, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
				3'b011: return tagged Valid tagged Binary { op: Sltu, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
				3'b100: return tagged Valid tagged Binary { op: Xor, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
				3'b101: case (pack(i_imm)[11:5]) matches
					7'b0000000: return tagged Valid tagged Binary { op: Srl, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
					7'b0100000: return tagged Valid tagged Binary { op: Sra, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
					default: return tagged Invalid;
				endcase
				3'b110: return tagged Valid tagged Binary { op: Or, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
				3'b111: return tagged Valid tagged Binary { op: And, rd: rd, rs1: rs1, rs2: tagged Right i_imm };
			endcase

			OpCode_Auipc: return tagged Valid tagged Auipc { rd: rd, imm: u_imm };

			OpCode_Store: case (parse_store_op(funct3)) matches
				tagged Invalid: return tagged Invalid;

				tagged Valid .op: return tagged Valid tagged Store { op: op, base: rs1, value: tagged Left rs2, offset: s_imm };
			endcase

			OpCode_Op: case ({ funct3, funct7 }) matches
				10'b000_0000000: return tagged Valid tagged Binary { op: Add, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b000_0100000: return tagged Valid tagged Binary { op: Sub, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b001_0000000: return tagged Valid tagged Binary { op: Sll, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b010_0000000: return tagged Valid tagged Binary { op: Slt, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b011_0000000: return tagged Valid tagged Binary { op: Sltu, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b100_0000000: return tagged Valid tagged Binary { op: Xor, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b101_0000000: return tagged Valid tagged Binary { op: Srl, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b101_0100000: return tagged Valid tagged Binary { op: Sra, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b110_0000000: return tagged Valid tagged Binary { op: Or, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				10'b111_0000000: return tagged Valid tagged Binary { op: And, rd: rd, rs1: rs1, rs2: tagged Left rs2 };
				default: return tagged Invalid;
			endcase

			OpCode_Lui: return tagged Valid tagged Li { rd: rd, imm: u_imm };

			OpCode_Branch: case (parse_branch_op(funct3)) matches
				tagged Invalid: return tagged Invalid;

				tagged Valid .op: return tagged Valid tagged Branch { op: op, rs1: rs1, rs2: tagged Left rs2, offset: b_imm };
			endcase

			OpCode_Jalr: case (funct3) matches
				3'b000: return tagged Valid tagged Jal { rd: rd, base: tagged XReg rs1, offset: extend(i_imm) };

				default: return tagged Invalid;
			endcase

			OpCode_Jal: return tagged Valid tagged Jal { rd: rd, base: tagged Pc, offset: j_imm };

			OpCode_System: case (funct3) matches
				3'b000: return tagged Valid tagged Ebreak;

				default: return tagged Invalid;
			endcase

			default: return tagged Invalid;
		endcase
	end
endfunction

function Maybe#(BranchOp) parse_branch_op(Bit#(3) funct3);
	case (funct3) matches
		3'b000: return tagged Valid Equal;
		3'b001: return tagged Valid NotEqual;
		3'b100: return tagged Valid LessThan;
		3'b101: return tagged Valid GreaterThanOrEqual;
		3'b110: return tagged Valid LessThanUnsigned;
		3'b111: return tagged Valid GreaterThanOrEqualUnsigned;
		default: return tagged Invalid;
	endcase
endfunction

function Maybe#(LoadOp) parse_load_op(Bit#(3) funct3);
	case (funct3) matches
		3'b000: return tagged Valid Byte;
		3'b001: return tagged Valid HalfWord;
		3'b010: return tagged Valid Word;
		3'b100: return tagged Valid ByteUnsigned;
		3'b101: return tagged Valid HalfWordUnsigned;
		default: return tagged Invalid;
	endcase
endfunction

function Maybe#(StoreOp) parse_store_op(Bit#(3) funct3);
	case (funct3) matches
		3'b000: return tagged Valid Byte;
		3'b001: return tagged Valid HalfWord;
		3'b010: return tagged Valid Word;
		default: return tagged Invalid;
	endcase
endfunction
