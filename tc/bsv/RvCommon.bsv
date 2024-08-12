typedef union tagged {
	left Left;
	right Right;
} Either#(type left, type right) deriving(Bits);

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
	struct { XReg rd; Int#(20) imm; } Auipc;

	struct { BinaryOp op; XReg rd; x_reg_src rs1; x_reg_src rs2; } Binary;

	struct { BranchOp op; x_reg_src rs1; x_reg_src rs2; Int#(12) imm; } Branch;

	void Ebreak;

	void Fence;

	struct { JalOp#(x_reg_src) op; XReg rd; } Jal;

	struct { LoadOp op; XReg rd; x_reg_src base; Int#(12) offset; } Load;

	struct { XReg rd; Int#(20) imm; } Lui;

	struct { StoreOp op; x_reg_src base; x_reg_src value; Int#(12) offset; } Store;
} Instruction#(type x_reg_src) deriving(Bits);

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
	struct { Int#(20) offset; } Pc;
	struct { x_reg_src base; Int#(12) offset; } XReg;
} JalOp#(type x_reg_src) deriving(Bits);

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
