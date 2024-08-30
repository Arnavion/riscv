import RvCommon::*;

interface RvDecoder;
	method Maybe#(Instruction#(Either#(XReg, Int#(64)), Csr, Csr)) decode(Bit#(32) in);
endinterface

(* synthesize *)
module mkRvDecoder(RvDecoder);
	method Maybe#(Instruction#(Either#(XReg, Int#(64)), Csr, Csr)) decode(Bit#(32) in);
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
			Int#(12) s_imm = unpack({ in[31:25], in[11:7] });
			Int#(12) b_imm = unpack({ in[31], in[7], in[30:25], in[11:8] });
			Int#(20) u_imm = unpack(in[31:12]);
			Int#(20) j_imm = unpack({ in[31], in[19:12], in[20], in[30:21] });

			case (opcode) matches
				OpCode_Load: case (parse_load_op(funct3)) matches
					tagged Invalid: return tagged Invalid;

					tagged Valid .op: return tagged Valid tagged Load { op: op, rd: rd, base: tagged Left rs1, offset: i_imm };
				endcase

				OpCode_MiscMem: return tagged Valid Fence;

				OpCode_OpImm: case (funct3) matches
					3'b000: return tagged Valid tagged Binary { op: Add, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
					3'b001: case (pack(i_imm)[11:6]) matches
						6'b000000: return tagged Valid tagged Binary { op: Sll, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
						default: return tagged Invalid;
					endcase
					3'b010: return tagged Valid tagged Binary { op: Slt, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
					3'b011: return tagged Valid tagged Binary { op: Sltu, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
					3'b100: return tagged Valid tagged Binary { op: Xor, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
					3'b101: case (pack(i_imm)[11:6]) matches
						6'b000000: return tagged Valid tagged Binary { op: Srl, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
						6'b010000: return tagged Valid tagged Binary { op: Sra, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
						default: return tagged Invalid;
					endcase
					3'b110: return tagged Valid tagged Binary { op: Or, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
					3'b111: return tagged Valid tagged Binary { op: And, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
				endcase

				OpCode_Auipc: return tagged Valid tagged Auipc { rd: rd, imm: u_imm };

				OpCode_OpImm32: case (funct3) matches
					3'b000: return tagged Valid tagged Binary { op: Addw, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
					3'b001: case (pack(i_imm)[11:5]) matches
						7'b0000000: return tagged Valid tagged Binary { op: Sllw, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
						default: return tagged Invalid;
					endcase
					3'b101: case (pack(i_imm)[11:5]) matches
						7'b0000000: return tagged Valid tagged Binary { op: Srlw, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
						7'b0100000: return tagged Valid tagged Binary { op: Sraw, rd: rd, rs1: tagged Left rs1, rs2: tagged Right extend(i_imm) };
						default: return tagged Invalid;
					endcase
					default: return tagged Invalid;
				endcase

				OpCode_Store: case (parse_store_op(funct3)) matches
					tagged Invalid: return tagged Invalid;

					tagged Valid .op: return tagged Valid tagged Store { op: op, base: tagged Left rs1, value: tagged Left rs2, offset: s_imm };
				endcase

				OpCode_Op: case ({ funct3, funct7 }) matches
					10'b000_0000000: return tagged Valid tagged Binary { op: Add, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b000_0100000: return tagged Valid tagged Binary { op: Sub, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b001_0000000: return tagged Valid tagged Binary { op: Sll, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b010_0000000: return tagged Valid tagged Binary { op: Slt, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b011_0000000: return tagged Valid tagged Binary { op: Sltu, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b100_0000000: return tagged Valid tagged Binary { op: Xor, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b101_0000000: return tagged Valid tagged Binary { op: Srl, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b101_0100000: return tagged Valid tagged Binary { op: Sra, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b110_0000000: return tagged Valid tagged Binary { op: Or, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b111_0000000: return tagged Valid tagged Binary { op: And, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					default: return tagged Invalid;
				endcase

				OpCode_Lui: return tagged Valid tagged Lui { rd: rd, imm: u_imm };

				OpCode_Op32: case ({ funct3, funct7 }) matches
					10'b000_0000000: return tagged Valid tagged Binary { op: Addw, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b000_0100000: return tagged Valid tagged Binary { op: Subw, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b001_0000000: return tagged Valid tagged Binary { op: Sllw, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b101_0000000: return tagged Valid tagged Binary { op: Srlw, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					10'b101_0100000: return tagged Valid tagged Binary { op: Sraw, rd: rd, rs1: tagged Left rs1, rs2: tagged Left rs2 };
					default: return tagged Invalid;
				endcase

				OpCode_Branch: case (parse_branch_op(funct3)) matches
					tagged Invalid: return tagged Invalid;

					tagged Valid .op: return tagged Valid tagged Branch { op: op, rs1: tagged Left rs1, rs2: tagged Left rs2, imm: b_imm };
				endcase

				OpCode_Jalr: case (funct3) matches
					3'b000: return tagged Valid tagged Jal { op: tagged XReg { base: tagged Left rs1, offset: i_imm }, rd: rd };

					default: return tagged Invalid;
				endcase

				OpCode_Jal: return tagged Valid tagged Jal { op: tagged Pc { offset: j_imm }, rd: rd };

				OpCode_System: case (funct3) matches
					3'b000: return tagged Valid tagged Ebreak;

					3'b001:
						if (rd == 0)
							return tagged Valid tagged Csr tagged Csrs { rs1: tagged Left rs1, csrd: csr };
						else
							return tagged Valid tagged Csr tagged Csrrw { rd: rd, rs1: tagged Left rs1, csrd: csr, csrs: csr };

					3'b010:
						if (rs1 == 0)
							return tagged Valid tagged Csr tagged Csrr { rd: rd, csrs: csr };
						else
							return tagged Valid tagged Csr tagged Csrrs { rd: rd, rs1: tagged Left rs1, csrd: csr, csrs: csr };

					3'b011:
						if (rs1 == 0)
							return tagged Valid tagged Csr tagged Csrr { rd: rd, csrs: csr };
						else
							return tagged Valid tagged Csr tagged Csrrc { rd: rd, rs1: tagged Left rs1, csrd: csr, csrs: csr };

					3'b101:
						if (rd == 0)
							return tagged Valid tagged Csr tagged Csrs { rs1: tagged Right unpack(pack(extend(csrimm))), csrd: csr };
						else
							return tagged Valid tagged Csr tagged Csrrw { rd: rd, rs1: tagged Right unpack(pack(extend(csrimm))), csrd: csr, csrs: csr };

					3'b110:
						if (csrimm == 0)
							return tagged Valid tagged Csr tagged Csrr { rd: rd, csrs: csr };
						else
							return tagged Valid tagged Csr tagged Csrrs { rd: rd, rs1: tagged Right unpack(pack(extend(csrimm))), csrd: csr, csrs: csr };

					3'b111:
						if (csrimm == 0)
							return tagged Valid tagged Csr tagged Csrr { rd: rd, csrs: csr };
						else
							return tagged Valid tagged Csr tagged Csrrc { rd: rd, rs1: tagged Right unpack(pack(extend(csrimm))), csrd: csr, csrs: csr };

					default: return tagged Invalid;
				endcase

				default: return tagged Invalid;
			endcase
		end
	endmethod
endmodule

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
		3'b011: return tagged Valid DoubleWord;
		3'b100: return tagged Valid ByteUnsigned;
		3'b101: return tagged Valid HalfWordUnsigned;
		3'b110: return tagged Valid WordUnsigned;
		default: return tagged Invalid;
	endcase
endfunction

function Maybe#(StoreOp) parse_store_op(Bit#(3) funct3);
	case (funct3) matches
		3'b000: return tagged Valid Byte;
		3'b001: return tagged Valid HalfWord;
		3'b010: return tagged Valid Word;
		3'b011: return tagged Valid DoubleWord;
		default: return tagged Invalid;
	endcase
endfunction
