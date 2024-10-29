typedef Bit#(5) XReg;

typedef Bit#(12) Csr;

typedef enum {
	OpCode_Load = 5'b00000,
	OpCode_LoadFp = 5'b00001,
	OpCode_MiscMem = 5'b00011,
	OpCode_OpImm = 5'b00100,
	OpCode_Auipc = 5'b00101,
	OpCode_OpImm32 = 5'b00110,
	OpCode_Store = 5'b01000,
	OpCode_StoreFp = 5'b01001,
	OpCode_Op = 5'b01100,
	OpCode_Lui = 5'b01101,
	OpCode_Op32 = 5'b01110,
	OpCode_Branch = 5'b11000,
	OpCode_Jalr = 5'b11001,
	OpCode_Jal = 5'b11011,
	OpCode_System = 5'b11100
} OpCode deriving(Bits);

function OpCode opcode_load(Bit#(1) fp) = unpack({ 4'b0000, fp });

function OpCode opcode_opimm(Bit#(1) w) = unpack({ 3'b001, w, 1'b0 });

function OpCode opcode_store(Bit#(1) fp) = unpack({ 4'b0100, fp });

typedef union tagged {
	struct { XReg rd; Int#(32) imm; } Auipc;

	struct { BinaryOp op; XReg rd; rs1_src rs1; rs2_src rs2; } Binary;

	struct { BranchOp op; rs1_src rs1; rs2_src rs2; Int#(32) offset; } Branch;

	struct { CsrOp op; XReg rd; Csr csrd; csr_src csrs; rs2_src rs2; } Csr;

	void Ebreak;

	void Fence;

	struct { XReg rd; JalBase#(rs1_src) base; Int#(32) offset; } Jal;

	struct { XReg rd; Int#(32) imm; } Li;

	struct { LoadOp op; XReg rd; rs1_src base; Int#(32) offset; } Load;

	struct { StoreOp op; rs1_src base; rs2_src value; Int#(32) offset; } Store;

	struct { UnaryOp op; XReg rd; rs1_src rs; } Unary;
} Instruction#(type rs1_src, type rs2_src, type csr_src);

typedef enum {
	Add,
	AddUw,
	Addw,
	And,
	Andn,
	Bclr,
	Bext,
	Binv,
	Bset,
	CzeroEqz,
	CzeroNez,
	Max,
	Maxu,
	Min,
	Minu,
	Or,
	Orn,
	Rol,
	Rolw,
	Ror,
	Rorw,
	Sh1add,
	Sh1addUw,
	Sh2add,
	Sh2addUw,
	Sh3add,
	Sh3addUw,
	Sll,
	SllUw,
	Sllw,
	Slt,
	Sltu,
	Sra,
	Sraw,
	Srl,
	Srlw,
	Sub,
	Subw,
	Xnor,
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

typedef enum {
	Csrrw,
	Csrrs,
	Csrrc
} CsrOp deriving(Bits);

typedef union tagged {
	void Pc;
	rs1_src XReg;
} JalBase#(type rs1_src) deriving(Bits);

typedef enum {
	Byte,
	ByteUnsigned,
	HalfWord,
	HalfWordUnsigned,
	Word,
	WordUnsigned,
	DoubleWord
} LoadOp deriving(Bits);

typedef enum {
	Byte,
	HalfWord,
	Word,
	DoubleWord
} StoreOp deriving(Bits);

typedef enum {
	Clz,
	Clzw,
	Cpop,
	Cpopw,
	Ctz,
	Ctzw,
	OrcB,
	Rev8,
	SextB,
	SextH,
	ZextH
} UnaryOp deriving(Bits);

// Raw binary representation of instructions, to ensure that fields remain at constant offsets across all ops.
typedef struct {
	RawOp op;
	XReg rd;
	Bit#(TMax#(SizeOf#(rs1_src), SizeOf#(csr_src))) rs1;
	Bit#(SizeOf#(rs2_src)) rs2;
	Int#(32) imm;
} RawInstruction#(type rs1_src, type rs2_src, type csr_src) deriving(Bits);

typedef union tagged {
	void Auipc;
	BinaryOp Binary;
	BranchOp Branch;
	CsrOp Csr;
	void Ebreak;
	void Fence;
	void Jal;
	void Jalr;
	void Li;
	LoadOp Load;
	StoreOp Store;
	UnaryOp Unary;
} RawOp deriving(Bits);

instance Bits#(Instruction#(rs1_src, rs2_src, csr_src), inst_len)
provisos (
	Bits#(rs1_src, rs1_src_len),
	Bits#(rs2_src, rs2_src_len),
	Bits#(csr_src, csr_src_len),
	Bits#(RawInstruction#(rs1_src, rs2_src, csr_src), inst_len)
);
	function Bit#(inst_len) pack(Instruction#(rs1_src, rs2_src, csr_src) inst);
		RawInstruction#(rs1_src, rs2_src, csr_src) result = RawInstruction {
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

			tagged Csr { op: .op, rd: .rd, csrd: .csrd, csrs: .csrs, rs2: .rs2 }: begin
				result.op = tagged Csr op;
				result.rd = rd;
				result.rs1 = { ?, pack(csrs) };
				result.rs2 = pack(rs2);
				result.imm = unpack({ ?, csrd });
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

			tagged Unary { op: .op, rd: .rd, rs: .rs }: begin
				result.op = tagged Unary op;
				result.rd = rd;
				result.rs1 = { ?, pack(rs) };
			end
		endcase

		return pack(result);
	endfunction

	function Instruction#(rs1_src, rs2_src, csr_src) unpack(Bit#(inst_len) bits);
		RawInstruction#(rs1_src, rs2_src, csr_src) inst = unpack(bits);

		rs1_src rs1 = unpack(truncate(inst.rs1));
		csr_src csrs = unpack(truncate(inst.rs1));
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

			tagged Csr .op: return tagged Csr {
				op: op,
				rd: inst.rd,
				csrd: truncate(pack(inst.imm)),
				csrs: csrs,
				rs2: rs2
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

			tagged Unary .op: return tagged Unary {
				op: op,
				rd: inst.rd,
				rs: rs1
			};
		endcase
	endfunction
endinstance
