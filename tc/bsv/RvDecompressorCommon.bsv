import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import Common::*;
import RvCommon::*;

typedef Server#(RvDecompressorRequest, RvDecompressorResponse) RvDecompressor;

typedef struct {
	Bit#(32) in;
} RvDecompressorRequest deriving(Bits);

typedef struct {
	Maybe#(DecompressedInstruction) inst;
} RvDecompressorResponse deriving(Bits, Eq);

typedef union tagged {
	Bit#(32) Compressed;
	Bit#(32) Uncompressed;
} DecompressedInstruction deriving(Bits, Eq);

function Bit#(30) type_r(
	OpCode opcode,
	XReg rd,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(7) funct7
) = { funct7, rs2, rs1, funct3, rd, pack(opcode) };

function Bit#(30) type_i(
	OpCode opcode,
	XReg rd,
	Bit#(3) funct3,
	XReg rs1,
	Bit#(12) imm
) = { imm, rs1, funct3, rd, pack(opcode) };

function Bit#(30) type_s(
	OpCode opcode,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(12) imm
) = { imm[11:5], rs2, rs1, funct3, imm[4:0], pack(opcode) };

function Bit#(30) type_b(
	OpCode opcode,
	Bit#(3) funct3,
	XReg rs1,
	XReg rs2,
	Bit#(12) imm
) = { imm[11], imm[9:4], rs2, rs1, funct3, imm[3:0], imm[10], pack(opcode) };

function Bit#(30) type_u(
	OpCode opcode,
	XReg rd,
	Bit#(20) imm
) = { imm, rd, pack(opcode) };

function Bit#(30) type_j(
	OpCode opcode,
	XReg rd,
	Bit#(20) imm
) = { imm[19], imm[9:0], imm[10], imm[18:11], rd, pack(opcode) };

`ifdef TESTING
import BuildVector::*;
import StmtFSM::*;
import Vector::*;

instance FShow#(RvDecompressorResponse);
	function Fmt fshow(RvDecompressorResponse response);
		case (response.inst) matches
			tagged Invalid: return $format("Invalid");
			tagged Valid (tagged Compressed .inst): return $format("Valid Compressed 0x%h", inst);
			tagged Valid (tagged Uncompressed .inst): return $format("Valid Uncompressed 0x%h", inst);
		endcase
	endfunction
endinstance

module mkTestDecompressorModule#(RvDecompressor decompressor32, RvDecompressor decompressor64)();
	let test_cases32 = vec(
		// All zeros
		TestCase {
			request: RvDecompressorRequest { in: 32'b0 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// addi4spn
		TestCase {
			request: RvDecompressorRequest { in: 32'b000_01010101_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000101011000_00010_000_01010_00100_11 }
		},
		// fld
		TestCase {
			request: RvDecompressorRequest { in: 32'b001_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000001010000_01010_011_01010_00001_11 }
		},
		// lw
		TestCase {
			request: RvDecompressorRequest { in: 32'b010_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000001010000_01010_010_01010_00000_11 }
		},
		// flw
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000001010000_01010_010_01010_00001_11 }
		},
		// Zcb
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_00000000000_00 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// fsd
		TestCase {
			request: RvDecompressorRequest { in: 32'b101_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000010_01010_01010_011_10000_01001_11 }
		},
		// sw
		TestCase {
			request: RvDecompressorRequest { in: 32'b110_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000010_01010_01010_010_10000_01000_11 }
		},
		// fsw
		TestCase {
			request: RvDecompressorRequest { in: 32'b111_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000010_01010_01010_010_10000_01001_11 }
		},
		// addi
		TestCase {
			request: RvDecompressorRequest { in: 32'b000_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_01010_000_01010_00100_11 }
		},
		// jal
		TestCase {
			request: RvDecompressorRequest { in: 32'b001_01010101010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b00010101101000000000_00001_11011_11 }
		},
		// li
		TestCase {
			request: RvDecompressorRequest { in: 32'b010_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_00000_000_01010_00100_11 }
		},
		// addi16sp
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_1_00010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111011000000_00010_000_00010_00100_11 }
		},
		// lui
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b11111111111111101010_01010_01101_11 }
		},
		// srli
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_00_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000101010_01010_101_01010_00100_11 }
		},
		// srai
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_01_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b010000101010_01010_101_01010_00100_11 }
		},
		// andi
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_10_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_01010_111_01010_00100_11 }
		},
		// sub
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_00_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0100000_01010_01010_000_01010_01100_11 }
		},
		// xor
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_01_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_100_01010_01100_11 }
		},
		// or
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_10_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_110_01010_01100_11 }
		},
		// and
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_11_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_111_01010_01100_11 }
		},
		// subw
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_00_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// addw
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_01_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// Reserved
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_10_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// Reserved
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_11_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// j
		TestCase {
			request: RvDecompressorRequest { in: 32'b101_01010101010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b00010101101000000000_00000_11011_11 }
		},
		// beqz
		TestCase {
			request: RvDecompressorRequest { in: 32'b110_101_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b1111010_00000_01010_000_01011_11000_11 }
		},
		// bnez
		TestCase {
			request: RvDecompressorRequest { in: 32'b111_101_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b1111010_00000_01010_001_01011_11000_11 }
		},
		// slli
		TestCase {
			request: RvDecompressorRequest { in: 32'b000_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b00000101010_01010_001_01010_00100_11 }
		},
		// fldsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b001_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000010101000_00010_011_01010_00001_11 }
		},
		// lwsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b010_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000010101000_00010_010_01010_00000_11 }
		},
		// flwsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000010101000_00010_010_01010_00001_11 }
		},
		// jr
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_0_01010_00000_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000000000_01010_000_00000_11001_11 }
		},
		// mv
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_0_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_00000_000_01010_01100_11 }
		},
		// ebreak
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_00000_00000_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000000001_00000_000_00000_11100_11 }
		},
		// jalr
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_01010_00000_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000000000_01010_000_00001_11001_11 }
		},
		// add
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_000_01010_01100_11 }
		},
		// fsdsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b101_101010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000101_01010_00010_011_01000_01001_11 }
		},
		// swsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b110_101010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000101_01010_00010_010_01000_01000_11 }
		},
		// fswsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b111_101010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000101_01010_00010_010_01000_01001_11 }
		},
		// uncompressed
		TestCase {
			request: RvDecompressorRequest { in: 32'b000000000000_00000_000_00000_00100_11 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Uncompressed 32'b000000000000_00000_000_00000_00100_11 }
		}
	);

	let test_cases64 = vec(
		// All zeros
		TestCase {
			request: RvDecompressorRequest { in: 32'b0 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// addi4spn
		TestCase {
			request: RvDecompressorRequest { in: 32'b000_01010101_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000101011000_00010_000_01010_00100_11 }
		},
		// fld
		TestCase {
			request: RvDecompressorRequest { in: 32'b001_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000001010000_01010_011_01010_00001_11 }
		},
		// lw
		TestCase {
			request: RvDecompressorRequest { in: 32'b010_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000001010000_01010_010_01010_00000_11 }
		},
		// ld
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000001010000_01010_011_01010_00000_11 }
		},
		// Zcb
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_00000000000_00 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// fsd
		TestCase {
			request: RvDecompressorRequest { in: 32'b101_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000010_01010_01010_011_10000_01001_11 }
		},
		// sw
		TestCase {
			request: RvDecompressorRequest { in: 32'b110_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000010_01010_01010_010_10000_01000_11 }
		},
		// sd
		TestCase {
			request: RvDecompressorRequest { in: 32'b111_010_010_01_010_00 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000010_01010_01010_011_10000_01000_11 }
		},
		// addi
		TestCase {
			request: RvDecompressorRequest { in: 32'b000_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_01010_000_01010_00100_11 }
		},
		// addiw
		TestCase {
			request: RvDecompressorRequest { in: 32'b001_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_01010_000_01010_00110_11 }
		},
		// li
		TestCase {
			request: RvDecompressorRequest { in: 32'b010_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_00000_000_01010_00100_11 }
		},
		// addi16sp
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_1_00010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111011000000_00010_000_00010_00100_11 }
		},
		// lui
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_1_01010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b11111111111111101010_01010_01101_11 }
		},
		// srli
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_00_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000101010_01010_101_01010_00100_11 }
		},
		// srai
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_01_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b010000101010_01010_101_01010_00100_11 }
		},
		// andi
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_10_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b111111101010_01010_111_01010_00100_11 }
		},
		// sub
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_00_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0100000_01010_01010_000_01010_01100_11 }
		},
		// xor
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_01_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_100_01010_01100_11 }
		},
		// or
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_10_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_110_01010_01100_11 }
		},
		// and
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_011_010_11_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_111_01010_01100_11 }
		},
		// subw
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_00_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0100000_01010_01010_000_01010_01110_11 }
		},
		// addw
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_01_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_000_01010_01110_11 }
		},
		// Reserved
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_10_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// Reserved
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_111_010_11_010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Invalid }
		},
		// j
		TestCase {
			request: RvDecompressorRequest { in: 32'b101_01010101010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b00010101101000000000_00000_11011_11 }
		},
		// beqz
		TestCase {
			request: RvDecompressorRequest { in: 32'b110_101_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b1111010_00000_01010_000_01011_11000_11 }
		},
		// bnez
		TestCase {
			request: RvDecompressorRequest { in: 32'b111_101_010_01010_01 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b1111010_00000_01010_001_01011_11000_11 }
		},
		// slli
		TestCase {
			request: RvDecompressorRequest { in: 32'b000_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b00000101010_01010_001_01010_00100_11 }
		},
		// fldsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b001_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000010101000_00010_011_01010_00001_11 }
		},
		// lwsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b010_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000010101000_00010_010_01010_00000_11 }
		},
		// ldsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b011_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000010101000_00010_011_01010_00000_11 }
		},
		// jr
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_0_01010_00000_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000000000_01010_000_00000_11001_11 }
		},
		// mv
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_0_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_00000_000_01010_01100_11 }
		},
		// ebreak
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_00000_00000_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000000001_00000_000_00000_11100_11 }
		},
		// jalr
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_01010_00000_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b000000000000_01010_000_00001_11001_11 }
		},
		// add
		TestCase {
			request: RvDecompressorRequest { in: 32'b100_1_01010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000000_01010_01010_000_01010_01100_11 }
		},
		// fsdsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b101_101010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000101_01010_00010_011_01000_01001_11 }
		},
		// swsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b110_101010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000101_01010_00010_010_01000_01000_11 }
		},
		// sdsp
		TestCase {
			request: RvDecompressorRequest { in: 32'b111_101010_01010_10 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Compressed 32'b0000101_01010_00010_011_01000_01000_11 }
		},
		// uncompressed
		TestCase {
			request: RvDecompressorRequest { in: 32'b000000000000_00000_000_00000_00100_11 },
			expected_response: RvDecompressorResponse { inst: tagged Valid tagged Uncompressed 32'b000000000000_00000_000_00000_00100_11 }
		}
	);

	Reg#(RvDecompressorResponse) response <- mkRegU;

	function Stmt test_case_seq(RvDecompressor decompressor, TestCase test_case) = seq
		decompressor.request.put(test_case.request);
		response <= decompressor.response.first;
		decompressor.response.deq;
		assert_eq(
			test_case.expected_response,
			response,
			$swriteAV(
				"0x%h -> expected ",
				test_case.request.in,
				fshow(test_case.expected_response),
				" but got ",
				fshow(response)
			)
		);
	endseq;

	Reg#(UInt#(32)) i <- mkReg(0);

	function Stmt make_test_cases_seq(
		Vector#(n32, TestCase) test_cases32,
		Vector#(n64, TestCase) test_cases64
	) = seq
		for (i <= 0; i < fromInteger(valueOf(n32)); i <= i + 1) seq
			test_case_seq(decompressor32, test_cases32[i]);
		endseq

		for (i <= 0; i < fromInteger(valueOf(n64)); i <= i + 1) seq
			test_case_seq(decompressor64, test_cases64[i]);
		endseq
	endseq;

	let m <- mkTestModule(make_test_cases_seq(test_cases32, test_cases64));
	return m;
endmodule

typedef struct {
	RvDecompressorRequest request;
	RvDecompressorResponse expected_response;
} TestCase;
`endif
