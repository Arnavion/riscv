import RvCommon::*;

interface RvDecompressor;
	method Maybe#(DecompressedInstruction) decompress(Bit#(32) in);
endinterface

typedef union tagged {
	Bit#(32) Compressed;
	Bit#(32) Uncompressed;
} DecompressedInstruction deriving(Bits);

(* synthesize *)
module mkRvDecompressor#(parameter Bool rv64)(RvDecompressor);
	method Maybe#(DecompressedInstruction) decompress(Bit#(32) in);
		case (in[1:0]) matches
			2'b00: case (in[15:13]) matches
				3'b000: if (in[12:2] == 0)
					return tagged Invalid;
				else begin
					// addi4spn
					return tagged Valid tagged Compressed
						type_i(OpCode_OpImm, { 2'b01, in[4:2] }, 3'b000, 5'b00010, zeroExtend({ in[10:7], in[12:11], in[5], in[6], 2'b00 }));
				end

				// fld
				3'b001: return tagged Valid tagged Compressed
					type_i(OpCode_LoadFp, { 2'b01, in[4:2] }, 3'b011, { 2'b01, in[9:7] }, zeroExtend({ in[6:5], in[12:10], 3'b000 }));

				// lw
				3'b010: return tagged Valid tagged Compressed
					type_i(OpCode_Load, { 2'b01, in[4:2] }, 3'b010, { 2'b01, in[9:7] }, zeroExtend({ in[5], in[12:10], in[6], 2'b00 }));

				3'b011: if (rv64)
					// ld
					return tagged Valid tagged Compressed
						type_i(OpCode_Load, { 2'b01, in[4:2] }, 3'b011, { 2'b01, in[9:7] }, zeroExtend({ in[6:5], in[12:10], 3'b000 }));
				else
					// flw
					return tagged Valid tagged Compressed
						type_i(OpCode_LoadFp, { 2'b01, in[4:2] }, 3'b010, { 2'b01, in[9:7] }, zeroExtend({ in[5], in[12:10], in[6], 2'b00 }));

				3'b100: case (in[12:10]) matches
					// lbu
					3'b000: return tagged Valid tagged Compressed
						type_i(OpCode_Load, { 2'b01, in[4:2] }, 3'b100, { 2'b01, in[9:7] }, zeroExtend({ in[5], in[6] }));

					// lhu / lh
					3'b001: return tagged Valid tagged Compressed
						type_i(OpCode_Load, { 2'b01, in[4:2] }, {~in[6], 2'b01}, { 2'b01, in[9:7] }, zeroExtend({ in[5], 1'b0 }));

					// sb
					3'b010: return tagged Valid tagged Compressed
						type_s(OpCode_Store, 3'b000, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, zeroExtend({ in[5], in[6] }));

					// sh
					3'b011: return tagged Valid tagged Compressed
						type_s(OpCode_Store, 3'b001, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, zeroExtend({ in[5], 1'b0 }));

					default: return tagged Invalid;
				endcase

				// fsd
				3'b101: return tagged Valid tagged Compressed
					type_s(OpCode_StoreFp, 3'b011, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, zeroExtend({ in[6:5], in[12:10], 3'b000 }));

				// sw
				3'b110: return tagged Valid tagged Compressed
					type_s(OpCode_Store, 3'b010, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, zeroExtend({ in[5], in[12:10], in[6], 2'b00 }));

				3'b111: if (rv64)
					// sd
					return tagged Valid tagged Compressed
						type_s(OpCode_Store, 3'b011, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, zeroExtend({ in[6:5], in[12:10], 3'b000 }));
				else
					// fsw
					return tagged Valid tagged Compressed
						type_s(OpCode_StoreFp, 3'b010, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, zeroExtend({ in[5], in[12:10], in[6], 2'b00 }));
			endcase

			2'b01: case (in[15:13]) matches
				// addi
				3'b000: return tagged Valid tagged Compressed
					type_i(OpCode_OpImm, in[11:7], 3'b000, in[11:7], signExtend({ in[12], in[6:2] }));

				3'b001: if (rv64)
					// addiw
					return tagged Valid tagged Compressed
						type_i(OpCode_OpImm32, in[11:7], 3'b000, in[11:7], signExtend({ in[12], in[6:2] }));
				else
					// jal
					return tagged Valid tagged Compressed
						type_j(OpCode_Jal, 5'b00001, signExtend({ in[12], in[8], in[10:9], in[6], in[7], in[2], in[11], in[5:3] }));

				// li
				3'b010: return tagged Valid tagged Compressed
					type_i(OpCode_OpImm, in[11:7], 3'b000, 5'b00000, signExtend({ in[12], in[6:2] }));

				3'b011: if (in[11:7] == 5'b00010)
					// addi16sp
					return tagged Valid tagged Compressed
						type_i(OpCode_OpImm, in[11:7], 3'b000, in[11:7], signExtend({ in[12], in[4:3], in[5], in[2], in[6], 4'b0000 }));
				else
					// lui
					return tagged Valid tagged Compressed
						type_u(OpCode_Lui, in[11:7], signExtend({ in[12], in[6:2] }));

				3'b100: case (in[11:10]) matches
					// srli
					2'b00: return tagged Valid tagged Compressed
						type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b101, { 2'b01, in[9:7] }, { 6'b000000, in[12], in[6:2] });

					// srai
					2'b01: return tagged Valid tagged Compressed
						type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b101, { 2'b01, in[9:7] }, { 6'b010000, in[12], in[6:2] });

					// andi
					2'b10: return tagged Valid tagged Compressed
						type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b111, { 2'b01, in[9:7] }, signExtend({ in[12], in[6:2] }));

					2'b11: case ({in[12], in[6:5]}) matches
						// sub
						3'b000: return tagged Valid tagged Compressed
							type_r(OpCode_Op, { 2'b01, in[9:7] }, 3'b000, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, 7'b0100000);

						// xor
						3'b001: return tagged Valid tagged Compressed
							type_r(OpCode_Op, { 2'b01, in[9:7] }, 3'b100, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, 7'b0000000);

						// or
						3'b010: return tagged Valid tagged Compressed
							type_r(OpCode_Op, { 2'b01, in[9:7] }, 3'b110, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, 7'b0000000);

						// and
						3'b011: return tagged Valid tagged Compressed
							type_r(OpCode_Op, { 2'b01, in[9:7] }, 3'b111, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, 7'b0000000);

						3'b100: if (rv64)
							// subw
							return tagged Valid tagged Compressed
								type_r(OpCode_Op32, { 2'b01, in[9:7] }, 3'b000, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, 7'b0100000);
						else
							return tagged Invalid;

						3'b101: if (rv64)
							// addw
							return tagged Valid tagged Compressed
								type_r(OpCode_Op32, { 2'b01, in[9:7] }, 3'b000, { 2'b01, in[9:7] }, { 2'b01, in[4:2] }, 7'b0000000);
						else
							return tagged Invalid;

						3'b111: case (in[4:2]) matches
							// zext.b
							3'b000: return tagged Valid tagged Compressed
								type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b111, { 2'b01, in[9:7] }, 12'b000011111111);

							3'b100: if (rv64)
								// zext.w
								return tagged Valid tagged Compressed
									type_r(OpCode_Op32, { 2'b01, in[9:7] }, 3'b000, { 2'b01, in[9:7] }, 5'b00000, 7'b0000100);
							else
								return tagged Invalid;

							// not
							3'b101: return tagged Valid tagged Compressed
								type_i(OpCode_OpImm, { 2'b01, in[9:7] }, 3'b100, { 2'b01, in[9:7] }, 12'b111111111111);

							default: return tagged Invalid;
						endcase

						default: return tagged Invalid;
					endcase
				endcase

				// j
				3'b101: return tagged Valid tagged Compressed
					type_j(OpCode_Jal, 5'b00000, signExtend({ in[12], in[8], in[10:9], in[6], in[7], in[2], in[11], in[5:3] }));

				// beqz
				3'b110: return tagged Valid tagged Compressed
					type_b(OpCode_Branch, 3'b000, { 2'b01, in[9:7] }, 5'b00000, signExtend({ in[12], in[6:5], in[2], in[11:10], in[4:3] }));

				// bnez
				3'b111: return tagged Valid tagged Compressed
					type_b(OpCode_Branch, 3'b001, { 2'b01, in[9:7] }, 5'b00000, signExtend({ in[12], in[6:5], in[2], in[11:10], in[4:3] }));
			endcase

			2'b10: case (in[15:13]) matches
				// slli
				3'b000: return tagged Valid tagged Compressed
					type_i(OpCode_OpImm, in[11:7], 3'b001, in[11:7], { 6'b000000, in[12], in[6:2] });

				// fldsp
				3'b001: return tagged Valid tagged Compressed
					type_i(OpCode_LoadFp, in[11:7], 3'b011, 5'b00010, zeroExtend({ in[4:2], in[12], in[6:5], 3'b000 }));

				// lwsp
				3'b010: return tagged Valid tagged Compressed
					type_i(OpCode_Load, in[11:7], 3'b010, 5'b00010, zeroExtend({ in[3:2], in[12], in[6:4], 2'b00 }));

				3'b011: if (rv64)
					// ldsp
					return tagged Valid tagged Compressed
						type_i(OpCode_Load, in[11:7], 3'b011, 5'b00010, zeroExtend({ in[4:2], in[12], in[6:5], 3'b000 }));
				else
					// flwsp
					return tagged Valid tagged Compressed
						type_i(OpCode_LoadFp, in[11:7], 3'b010, 5'b00010, zeroExtend({ in[3:2], in[12], in[6:4], 2'b00 }));

				3'b100: case ({ | in[11:7], | in[6:2] }) matches
					2'b00: if (unpack(in[12]))
						// ebreak
						return tagged Valid tagged Compressed
							type_r(OpCode_System, 5'b00000, 3'b000, 5'b00000, 5'b00001, 7'b0000000);
					else return tagged Invalid;

					// jr, jalr
					2'b10: return tagged Valid tagged Compressed
						type_i(OpCode_Jalr, { 4'b0000, in[12] }, 3'b000, in[11:7], '0);

					// mv, add
					2'b11: return tagged Valid tagged Compressed
						type_r(OpCode_Op, in[11:7], 3'b000, { in[12], in[12], in[12], in[12], in[12] } & in[11:7], in[6:2], 7'b0000000);

					default: return tagged Invalid;
				endcase

				// fsdsp
				3'b101: return tagged Valid tagged Compressed
					type_s(OpCode_StoreFp, 3'b011, 5'b00010, in[6:2], zeroExtend({ in[9:7], in[12:10], 3'b000 }));

				// swsp
				3'b110: return tagged Valid tagged Compressed
					type_s(OpCode_Store, 3'b010, 5'b00010, in[6:2], zeroExtend({ in[8:7], in[12:9], 2'b00 }));

				3'b111: if (rv64)
					// sdsp
					return tagged Valid tagged Compressed
						type_s(OpCode_Store, 3'b011, 5'b00010, in[6:2], zeroExtend({ in[9:7], in[12:10], 3'b000 }));
				else
					// fswsp
					return tagged Valid tagged Compressed
						type_s(OpCode_StoreFp, 3'b010, 5'b00010, in[6:2], zeroExtend({ in[8:7], in[12:9], 2'b00 }));
			endcase

			// uncompressed
			2'b11: return tagged Valid tagged Uncompressed ({ in[31:2], 2'b11 });
		endcase
	endmethod
endmodule

function Bit#(32) type_r(
	OpCode opcode,
	XReg rd,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(7) funct7
);
	return { funct7, rs2, rs1, funct3, rd, pack(opcode), 2'b11 };
endfunction

function Bit#(32) type_i(
	OpCode opcode,
	XReg rd,
	Bit#(3) funct3,
	XReg rs1,
	Bit#(12) imm
);
	return { imm, rs1, funct3, rd, pack(opcode), 2'b11 };
endfunction

function Bit#(32) type_s(
	OpCode opcode,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(12) imm
);
	return { imm[11:5], rs2, rs1, funct3, imm[4:0], pack(opcode), 2'b11 };
endfunction

function Bit#(32) type_b(
	OpCode opcode,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(12) imm
);
	return { imm[11], imm[9:4], rs2, rs1, funct3, imm[3:0], imm[10], pack(opcode), 2'b11 };
endfunction

function Bit#(32) type_u(
	OpCode opcode,
	XReg rd,
	Bit#(20) imm
);
	return { imm, rd, pack(opcode), 2'b11 };
endfunction

function Bit#(32) type_j(
	OpCode opcode,
	XReg rd,
	Bit#(20) imm
);
	return { imm[19], imm[9:0], imm[10], imm[18:11], rd, pack(opcode), 2'b11 };
endfunction
