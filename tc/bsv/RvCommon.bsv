typedef Bit#(5) XReg;

typedef enum {
	OpCode_Load = 5'b00000,
	OpCode_MiscMem = 5'b00011,
	OpCode_OpImm = 5'b00100,
	OpCode_Auipc = 5'b00101,
	OpCode_Store = 5'b01000,
	OpCode_Op = 5'b01100,
	OpCode_Lui = 5'b01101,
	OpCode_Branch = 5'b11000,
	OpCode_Jalr = 5'b11001,
	OpCode_Jal = 5'b11011,
	OpCode_System = 5'b11100
} OpCode deriving(Bits);

typedef union tagged {
	struct { XReg rd; Int#(32) imm; } Auipc;

	struct { BinaryOp op; XReg rd; rs1_src rs1; rs2_src rs2; } Binary;

	struct { BranchOp op; rs1_src rs1; rs2_src rs2; Int#(32) offset; } Branch;

	void Ebreak;

	void Fence;

	struct { XReg rd; JalBase#(rs1_src) base; Int#(32) offset; } Jal;

	struct { XReg rd; Int#(32) imm; } Li;

	struct { LoadOp op; XReg rd; rs1_src base; Int#(32) offset; } Load;

	struct { StoreOp op; rs1_src base; rs2_src value; Int#(32) offset; } Store;
} Instruction#(type rs1_src, type rs2_src);

typedef enum {
	Add,
	And,
	Or,
	Sll,
	Slt,
	Sltu,
	Sra,
	Srl,
	Sub,
	Xor
} BinaryOp deriving(Bits);

typedef enum {
	Equal,
	NotEqual,
	LessThan,
	GreaterThanOrEqual,
	LessThanUnsigned,
	GreaterThanOrEqualUnsigned
} BranchOp deriving(Bits);

typedef union tagged {
	void Pc;
	rs1_src XReg;
} JalBase#(type rs1_src) deriving(Bits);

typedef enum {
	Byte,
	ByteUnsigned,
	HalfWord,
	HalfWordUnsigned,
	Word
} LoadOp deriving(Bits);

typedef enum {
	Byte,
	HalfWord,
	Word
} StoreOp deriving(Bits);

// Raw binary representation of instructions, to ensure that fields remain at constant offsets across all ops.
typedef struct {
	RawOp op;
	XReg rd;
	Bit#(SizeOf#(rs1_src)) rs1;
	Bit#(SizeOf#(rs2_src)) rs2;
	Int#(32) imm;
} RawInstruction#(type rs1_src, type rs2_src) deriving(Bits);

typedef union tagged {
	void Auipc;
	BinaryOp Binary;
	BranchOp Branch;
	void Ebreak;
	void Fence;
	void Jal;
	void Jalr;
	void Li;
	LoadOp Load;
	StoreOp Store;
} RawOp deriving(Bits);

instance Bits#(Instruction#(rs1_src, rs2_src), inst_len)
provisos (
	Bits#(rs1_src, rs1_src_len),
	Bits#(rs2_src, rs2_src_len),
	Bits#(RawInstruction#(rs1_src, rs2_src), inst_len)
);
	function Bit#(inst_len) pack(Instruction#(rs1_src, rs2_src) inst);
		RawInstruction#(rs1_src, rs2_src) result = RawInstruction {
			op: ?,
			rd: ?,
			rs1: ?,
			rs2: ?,
			imm: ?
		};

		case (inst) matches
			tagged Auipc { rd: .rd, imm: .imm }: begin
				result.op = Auipc;
				result.rd = rd;
				result.imm = imm;
			end

			tagged Binary { op: .op, rd: .rd, rs1: .rs1, rs2: .rs2 }: begin
				result.op = tagged Binary op;
				result.rd = rd;
				result.rs1 = { ?, pack(rs1) };
				result.rs2 = pack(rs2);
			end

			tagged Branch { op: .op, rs1: .rs1, rs2: .rs2, offset: .offset }: begin
				result.op = tagged Branch op;
				result.rs1 = { ?, pack(rs1) };
				result.rs2 = pack(rs2);
				result.imm = offset;
			end

			tagged Ebreak: begin
				result.op = tagged Ebreak;
			end

			tagged Fence: begin
				result.op = tagged Fence;
			end

			tagged Jal { rd: .rd, base: .base, offset: .offset }: begin
				result.rd = rd;
				case (base) matches
					tagged Pc: begin
						result.op = tagged Jal;
					end

					tagged XReg .base: begin
						result.op = tagged Jalr;
						result.rs1 = { ?, pack(base) };
					end
				endcase
				result.imm = offset;
			end

			tagged Li { rd: .rd, imm: .imm }: begin
				result.op = Li;
				result.rd = rd;
				result.imm = imm;
			end

			tagged Load { op: .op, rd: .rd, base: .base, offset: .offset }: begin
				result.op = tagged Load op;
				result.rd = rd;
				result.rs1 = { ?, pack(base) };
				result.imm = offset;
			end

			tagged Store { op: .op, base: .base, value: .value, offset: .offset }: begin
				result.op = tagged Store op;
				result.rs1 = { ?, pack(base) };
				result.rs2 = pack(value);
				result.imm = offset;
			end
		endcase

		return pack(result);
	endfunction

	function Instruction#(rs1_src, rs2_src) unpack(Bit#(inst_len) bits);
		RawInstruction#(rs1_src, rs2_src) inst = unpack(bits);

		rs1_src rs1 = unpack(inst.rs1);
		rs2_src rs2 = unpack(inst.rs2);

		case (inst.op) matches
			tagged Auipc: return tagged Auipc {
				rd: inst.rd,
				imm: inst.imm
			};

			tagged Binary .op: return tagged Binary {
				op: op,
				rd: inst.rd,
				rs1: rs1,
				rs2: rs2
			};

			tagged Branch .op: return tagged Branch {
				op: op,
				rs1: rs1,
				rs2: rs2,
				offset: inst.imm
			};

			tagged Ebreak: return tagged Ebreak;

			tagged Fence: return tagged Fence;

			tagged Jal: return tagged Jal {
				rd: inst.rd,
				base: tagged Pc,
				offset: inst.imm
			};

			tagged Jalr: return tagged Jal {
				base: tagged XReg rs1,
				rd: inst.rd,
				offset: inst.imm
			};

			tagged Li: return tagged Li {
				rd: inst.rd,
				imm: inst.imm
			};

			tagged Load .op: return tagged Load {
				op: op,
				rd: inst.rd,
				base: rs1,
				offset: inst.imm
			};

			tagged Store .op: return tagged Store {
				op: op,
				base: rs1,
				value: rs2,
				offset: inst.imm
			};
		endcase
	endfunction
endinstance
