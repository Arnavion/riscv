typedef union tagged {
	left Left;
	right Right;
} Either#(type left, type right) deriving(Bits);

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

typedef union tagged {
	struct { XReg rd; Int#(20) imm; } Auipc;

	struct { BinaryOp op; XReg rd; x_reg_src rs1; x_reg_src rs2; } Binary;

	struct { BranchOp op; x_reg_src rs1; x_reg_src rs2; Int#(12) imm; } Branch;

	CsrOp#(x_reg_src, csr_dest, csr_src) Csr;

	void Ebreak;

	void Fence;

	struct { JalOp#(x_reg_src) op; XReg rd; } Jal;

	struct { LoadOp op; XReg rd; x_reg_src base; Int#(12) offset; } Load;

	struct { XReg rd; Int#(20) imm; } Lui;

	struct { StoreOp op; x_reg_src base; x_reg_src value; Int#(12) offset; } Store;
} Instruction#(type x_reg_src, type csr_dest, type csr_src) deriving(Bits);

typedef enum {
	Add,
	AddUw,
	Addw,
	And,
	Bclr,
	Bext,
	Binv,
	Bset,
	CzeroEqz,
	CzeroNez,
	Or,
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
	struct { XReg rd; csr_src csrs; } Csrr;
	struct { x_reg_src rs1; csr_dest csrd; } Csrs;
	struct { XReg rd; x_reg_src rs1; csr_dest csrd; csr_src csrs; } Csrrw;
	struct { XReg rd; x_reg_src rs1; csr_dest csrd; csr_src csrs; } Csrrs;
	struct { XReg rd; x_reg_src rs1; csr_dest csrd; csr_src csrs; } Csrrc;
} CsrOp#(type x_reg_src, type csr_dest, type csr_src) deriving(Bits);

typedef union tagged {
	struct { Int#(20) offset; } Pc;
	struct { x_reg_src base; Int#(12) offset; } XReg;
} JalOp#(type x_reg_src) deriving(Bits);

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
