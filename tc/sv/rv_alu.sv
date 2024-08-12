/*

rx   : rx as i64
rxw  : rx as i32 as i64 (sign-extended)
rxuw : rx as u32 as u64 (zero-extended)

op   : a op b
opw  : (a32 op32 b32) as i64 (sign-extended)

---

Inputs:
- opcode
- decode3(funct3)
- decode7(funct7)
- decode5(funct5) == decode(rs2)
- rs1
- rs2
- imm
- csrimm
- CSR Load Value
- pc
- pcnext = "pc" + "inst len" (precomputed at decode time using bespoke adder)
- RAM Load Value
- rd != x0
- rs1 != x0

Outputs:
- rd
- pcnext = "pcnext from +" ? "+" : "pcnext"
- RAM Load
- RAM Store
- RAM Address
- CSR Load
- CSR Store
- CSR Store Value

---

I

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |            Misc             |        rd         |
|                                 |        |        |        |        | -> |        in1        | in2  |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===================+======+===============+=============+===================+
| auipc rd, imm                   | 5      |        |        |        | -> | pc                | imm  |               |             | +                 |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+
| lui rd, imm                     | 13     |        |        |        | -> |                   |      |               |             | imm               |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+
| addi/addiw rd, rs1, imm         | 4/6    | 0      |        |        | -> | rs1               | imm  |               |             | +/+w              |
| add/addw rd, rs1, rs2           | 12/14  | 0      | 0      |        | -> | rs1               | rs2  |               |             | +/+w              |
| sub/subw rd, rs1, rs2           | 12/14  | 0      | 32     |        | -> | rs1               | -rs2 |               |             | +/+w              |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+
| slti rd, rs1, imm               | 4      | 2      |        |        | -> |                   |      | rs1           | imm         | <s                |
| sltiu rd, rs1, imm              | 4      | 3      |        |        | -> |                   |      | rs1           | imm         | <u                |
| xori rd, rs1, imm               | 4      | 4      |        |        | -> |                   |      | rs1           | imm         | ^                 |
| ori rd, rs1, imm                | 4      | 6      |        |        | -> |                   |      | rs1           | imm         | |                 |
| andi rd, rs1, imm               | 4      | 7      |        |        | -> |                   |      | rs1           | imm         | &                 |
| slli/slliw rd, rs1, imm         | 4/6    | 1      | 0/1    |        | -> |                   |      | rev8.b(rs1)   | imm         | rev8.b(>>)/w      |
| sll/sllw rd, rs1, rs2           | 12/14  | 1      | 0      |        | -> |                   |      | rev8.b(rs1)   | rs2         | rev8.b(>>)/w      |
| slt rd, rs1, rs2                | 12     | 2      | 0      |        | -> |                   |      | rs1           | rs2         | <s                |
| sltu rd, rs1, rs2               | 12     | 3      | 0      |        | -> |                   |      | rs1           | rs2         | <u                |
| xor rd, rs1, rs2                | 12     | 4      | 0      |        | -> |                   |      | rs1           | rs2         | ^                 |
| srli/srliw rd, rs1, imm         | 4/6    | 5      | 0/1    |        | -> |                   |      | rs1/rs1uw     | imm         | >>l               |
| srl/srlw rd, rs1, rs2           | 12/14  | 5      | 0      |        | -> |                   |      | rs1/rs1uw     | rs2         | >>l               |
| or rd, rs1, rs2                 | 12     | 6      | 0      |        | -> |                   |      | rs1           | rs2         | |                 |
| and rd, rs1, rs2                | 12     | 7      | 0      |        | -> |                   |      | rs1           | rs2         | &                 |
| srai/sraiw rd, rs1, imm         | 4/6    | 5      | 32/33  |        | -> |                   |      | rs1/rs1w      | imm         | >>a               |
| sra/sraw rd, rs1, rs2           | 12/14  | 5      | 32     |        | -> |                   |      | rs1/rs1w      | rs2         | >>a               |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-----------------------------+-------------------+--------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |            Misc             |        rd         | pcnext |
|                                 |        |        |        |        | -> |        in1        | in2  |      in3      |     in4     |                   | from + |
+=================================+========+========+========+========+====+===================+======+===============+=============+===================+========+
| jalr rd, imm(rs1)               | 25     |        |        |        | -> | rs1               | imm  |               |             | pcnext            | 1      |
| jal rd, imm                     | 27     |        |        |        | -> | pc                | imm  |               |             | pcnext            | 1      |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+--------+
| beq rs1, rs2, imm               | 24     | 0      |        |        | -> | pc                | imm  | rs1           | rs2         |                   | =      |
| bne rs1, rs2, imm               | 24     | 1      |        |        | -> | pc                | imm  | rs1           | rs2         |                   | !=     |
| blt rs1, rs2, imm               | 24     | 4      |        |        | -> | pc                | imm  | rs1           | rs2         |                   | <s     |
| bge rs1, rs2, imm               | 24     | 5      |        |        | -> | pc                | imm  | rs1           | rs2         |                   | !<s    |
| bltu rs1, rs2, imm              | 24     | 6      |        |        | -> | pc                | imm  | rs1           | rs2         |                   | <u     |
| bgeu rs1, rs2, imm              | 24     | 7      |        |        | -> | pc                | imm  | rs1           | rs2         |                   | !<u    |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+--------+

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-------------------+------+-------+---------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |        rd         | RAM  |  RAM  |   RAM   |
|                                 |        |        |        |        | -> |        in1        | in2  |                   | Load | Store | Address |
+=================================+========+========+========+========+====+===================+======+===================+======+=======+=========+
| lb rd, imm(rs1)                 | 0      | 0      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
| lh rd, imm(rs1)                 | 0      | 1      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
| lw rd, imm(rs1)                 | 0      | 2      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
| ld rd, imm(rs1)                 | 0      | 3      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
| lbu rd, imm(rs1)                | 0      | 4      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
| lhu rd, imm(rs1)                | 0      | 5      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
| lwu rd, imm(rs1)                | 0      | 6      |        |        | -> | rs1               | imm  | RAM Load Value    | 1    |       | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+
| sb rs2, imm(rs1)                | 8      | 0      |        |        | -> | rs1               | imm  |                   |      | 1     | +       |
| sh rs2, imm(rs1)                | 8      | 1      |        |        | -> | rs1               | imm  |                   |      | 1     | +       |
| sw rs2, imm(rs1)                | 8      | 2      |        |        | -> | rs1               | imm  |                   |      | 1     | +       |
| sd rs2, imm(rs1)                | 8      | 3      |        |        | -> | rs1               | imm  |                   |      | 1     | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+

---

Zicond

+---------------------------------+--------+--------+--------+--------+----+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |            Misc             |        rd         |
|                                 |        |        |        |        | -> |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===============+=============+===================+
| czero.eqz rd, rs1, rs2          | 12     | 5      | 7      |        | -> |               | rs2         | = ? 0 : rs1       |
| czero.nez rd, rs1, rs2          | 12     | 7      | 7      |        | -> |               | rs2         | = ? rs1 : 0       |
+---------------------------------+--------+--------+--------+--------+----+---------------+-------------+-------------------+

---

Zicsr

+---------------------------------+--------+--------+--------+--------+----+-----------------------------+-------------------+----------+-------------+-----------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |            Misc             |        rd         | CSR Load |  CSR Store  | CSR Store Value |
|                                 |        |        |        |        | -> |      in3      |     in4     |                   |          |             |                 |
+=================================+========+========+========+========+====+===============+=============+===================+==========+=============+=================+
| csrrw csr, rd, rs1              | 28     | 1      |        |        | -> |               |             | csr               | rd != x0 | 1           | rs1             |
| csrrs csr, rd, rs1              | 28     | 2      |        |        | -> | csr           | rs1         | csr               | 1        | rs1 != x0   | |               |
| csrrc csr, rd, rs1              | 28     | 3      |        |        | -> | csr           | ~rs1        | csr               | 1        | rs1 != x0   | &               |
| csrrwi csr, rd, csrimm          | 28     | 5      |        |        | -> |               |             | csr               | rd != x0 | 1           | csrimm          |
| csrrsi csr, rd, csrimm          | 28     | 6      |        |        | -> | csr           | csrimm      | csr               | 1        | csrimm != 0 | |               |
| csrrci csr, rd, csrimm          | 28     | 7      |        |        | -> | csr           | ~csrimm     | csr               | 1        | csrimm != 0 | &               |
+---------------------------------+--------+--------+--------+--------+----+---------------+-------------+-------------------+----------+-------------+-----------------+

---

Zba

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |            Misc             |        rd         |
|                                 |        |        |        |        | -> |        in1        | in2  |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===================+======+===============+=============+===================+
| add.uw rd, rs1, rs2             | 14     | 0      | 4      |        | -> | rs1uw             | rs2  |               |             | +                 |
| sh1add/sh1add.uw rd, rs1, rs2   | 12/14  | 2      | 16     |        | -> | rs1/rs1uw << 1    | rs2  |               |             | +                 |
| sh2add/sh2add.uw rd, rs1, rs2   | 12/14  | 4      | 16     |        | -> | rs1/rs1uw << 2    | rs2  |               |             | +                 |
| sh3add/sh3add.uw rd, rs1, rs2   | 12/14  | 6      | 16     |        | -> | rs1/rs1uw << 3    | rs2  |               |             | +                 |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+
| slli.uw rd, rs1, imm            | 6      | 1      | 4/5    |        | -> |                   |      | rev8.b(rs1uw) | imm         | rev8.b(>>)        |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+

---

Zbb

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-----------------------------+-------------------+-----------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |            Misc             |        rd         |   cpop    |
|                                 |        |        |        |        | -> |        in1        | in2  |      in3      |     in4     |                   |    in5    |
+=================================+========+========+========+========+====+===================+======+===============+=============+===================+===========+
| xnor rd, rs1, rs2               | 12     | 4      | 32     |        | -> |                   |      | rs1           | ~rs2        | ^                 |           |
| orn rd, rs1, rs2                | 12     | 6      | 32     |        | -> |                   |      | rs1           | ~rs2        | |                 |           |
| andn rd, rs1, rs2               | 12     | 7      | 32     |        | -> |                   |      | rs1           | ~rs2        | &                 |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+
| clz/clzw rd, rs1                | 4/6    | 1      | 48     | 0      | -> | rev8.b(rs1/rs1uw) | -1   | +             | ~in1        | cpop/cpopw        | &         |
| ctz/ctzw rs1                    | 4/6    | 1      | 48     | 1      | -> | rs1/rs1uw         | -1   | +             | ~in1        | cpop/cpopw        | &         |
| cpop/cpopw rd, rs1              | 4/6    | 1      | 48     | 2      | -> |                   |      |               |             | cpop              | rs1/rs1uw |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+
| min rd, rs1, rs2                | 12     | 4      | 5      |        | -> |                   |      | rs1           |  rs2        | <s ? rs1 : rs2    |           |
| minu rd, rs1, rs2               | 12     | 5      | 5      |        | -> |                   |      | rs1           |  rs2        | <u ? rs1 : rs2    |           |
| max rd, rs1, rs2                | 12     | 6      | 5      |        | -> |                   |      | rs1           |  rs2        | <s ? rs2 : rs1    |           |
| maxu rd, rs1, rs2               | 12     | 7      | 5      |        | -> |                   |      | rs1           |  rs2        | <u ? rs2 : rs1    |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+
| zext.h rd, rs1                  | 14     | 4      | 4      | 0      | -> |                   |      |               |             | rs1uh             |           |
| sext.b rd, rs1                  | 4      | 1      | 48     | 4      | -> |                   |      |               |             | rs1sb             |           |
| sext.h rd, rs1                  | 4      | 1      | 48     | 5      | -> |                   |      |               |             | rs1sh             |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+
| rol rd, rs1, rs2                | 12     | 1      | 48     |        | -> |                   |      | rs1           |  rs2        | rol               |           |
| rolw rd, rs1, rs2               | 14     | 1      | 48     |        | -> |                   |      | rs1uw:rs1uw   |  rs2        | rolw              |           |
| rori rd, rs1, imm               | 4      | 5      | 48/49  |        | -> |                   |      | rs1           |  imm        | ror               |           |
| roriw rd, rs1, imm              | 6      | 5      | 48     |        | -> |                   |      | rs1uw:rs1uw   |  imm        | rorw              |           |
| ror rd, rs1, rs2                | 12     | 5      | 48     |        | -> |                   |      | rs1           |  rs2        | ror               |           |
| rorw rd, rs1, rs2               | 14     | 5      | 48     |        | -> |                   |      | rs1uw:rs1uw   |  rs2        | rorw              |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+
| orc.b rd, rs1                   | 4      | 5      | 20     | 7      | -> |                   |      |               |             | orc.b(rs1)        |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+
| rev8 rd, rs1                    | 4      | 5      | 53     | 24     | -> |                   |      |               |             | rev8(rs1)         |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------+-------------+-------------------+-----------+

---

Zbs

+---------------------------------+--------+--------+--------+--------+----+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |            Misc             |        rd         |
|                                 |        |        |        |        | -> |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===============+=============+===================+
| bseti rd, rs1, imm              | 4      | 1      | 20/21  |        | -> | rs1           | 1 << imm    | |                 |
| bset rd, rs1, rs2               | 12     | 1      | 20     |        | -> | rs1           | 1 << rs2    | |                 |
| bclri rd, rs1, imm              | 4      | 1      | 36/37  |        | -> | rs1           | ~(1 << imm) | &                 |
| bclr rd, rs1, rs2               | 12     | 1      | 36     |        | -> | rs1           | ~(1 << rs2) | &                 |
| bexti rd, rs1, imm              | 4      | 5      | 36/37  |        | -> | rs1           | imm         | >> & 1            |
| bext rd, rs1, rs2               | 12     | 5      | 36     |        | -> | rs1           | rs2         | >> & 1            |
| binvi rd, rs1, imm              | 4      | 1      | 52/53  |        | -> | rs1           | 1 << imm    | ^                 |
| binv rd, rs1, rs2               | 12     | 1      | 52     |        | -> | rs1           | 1 << rs2    | ^                 |
+---------------------------------+--------+--------+--------+--------+----+---------------+-------------+-------------------+

---

Zbkb

+---------------------------------+--------+--------+--------+--------+----+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |        rd         |
|                                 |        |        |        |        | -> |                   |
+=================================+========+========+========+========+====+===================+
| rev.b rd, rs1                   | 4      | 5      | 52     | 7      | -> | rev.b             |
| pack rd, rs1, rs2               | 12     | 4      | 4      |        | -> | rs2uw:rs1uw       |
| packw rd, rs1, rs2              | 14     | 4      | 4      |        | -> | rs2uh:rs1uh       |
| packh rd, rs1, rs2              | 12     | 7      | 4      |        | -> | rs2ub:rs1ub       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+

---

Zbkx

+---------------------------------+--------+--------+--------+--------+----+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |            Misc             |        rd         |
|                                 |        |        |        |        | -> |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===============+=============+===================+
| xperm.n rd, rs1, rs2            | 12     | 2      | 20     |        | -> | rs1           | rs2         | xperm.n(rs1, rs2) |
| xperm.b rd, rs1, rs2            | 12     | 4      | 20     |        | -> | rs1           | rs2         | xperm.b(rs1, rs2) |
+---------------------------------+--------+--------+--------+--------+----+---------------+-------------+-------------------+

---

Zmmul

+---------------------------------+--------+--------+--------+--------+----+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |            Misc             |        rd         |
|                                 |        |        |        |        | -> |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===============+=============+===================+
| mul/mulw rd, rs1, rs2           | 12/14  | 0      | 1      |        | -> | rs1/rs1w      | rs2/rsw2    | *l / *w           |
| mulh rd, rs1, rs2               | 12     | 1      | 1      |        | -> | rs1           | rs2         | *hss              |
| mulhsu rd, rs1, rs2             | 12     | 2      | 1      |        | -> | rs1           | rs2         | *hsu              |
| mulhu rd, rs1, rs2              | 12     | 3      | 1      |        | -> | rs1           | rs2         | *huu              |
+---------------------------------+--------+--------+--------+--------+----+---------------+-------------+-------------------+

---

M

+---------------------------------+--------+--------+--------+--------+----+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |            Misc             |        rd         |
|                                 |        |        |        |        | -> |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===============+=============+===================+
| div rd, rs1, rs2                | 12     | 4      | 1      |        | -> | rs1           | rs2         | /                 |
| divw rd, rs1, rs2               | 14     | 4      | 1      |        | -> | rs1w          | rs2w        | /w                |
| divu rd, rs1, rs2               | 12     | 5      | 1      |        | -> | rs1           | rs2         | /u                |
| divuw rd, rs1, rs2              | 14     | 5      | 1      |        | -> | rs1uw         | rs2uw       | /uw               |
| rem rd, rs1, rs2                | 12     | 6      | 1      |        | -> | rs1           | rs2         | %                 |
| remw rd, rs1, rs2               | 14     | 6      | 1      |        | -> | rs1w          | rs2w        | %w                |
| remu rd, rs1, rs2               | 12     | 7      | 1      |        | -> | rs1           | rs2         | %u                |
| remuw rd, rs1, rs2              | 14     | 7      | 1      |        | -> | rs1uw         | rs2uw       | %uw               |
+---------------------------------+--------+--------+--------+--------+----+---------------+-------------+-------------------+

 */

module rv_alu (
	input bit[4:0] opcode,
	input bit[2:0] funct3,
	input bit[6:0] funct7,
	input logic[31:0] rs1,
	input logic[31:0] rs2,
	input logic[31:0] imm,
	input bit[31:2] pc,
	input bit[31:2] pcnext_in,
	input logic[31:0] ram_load_value,

	output bit sigill,
	output bit[31:1] pcnext_out,
	output logic[31:0] rd,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[31:0] ram_address,
	output logic[31:0] ram_store_value
);
	typedef enum bit[4:0] {
		OpCode_Load = 5'b00000,
		OpCode_OpImm = 5'b00100,
		OpCode_Auipc = 5'b00101,
		OpCode_Store = 5'b01000,
		OpCode_Op = 5'b01100,
		OpCode_Lui = 5'b01101,
		OpCode_Branch = 5'b11000,
		OpCode_Jalr = 5'b11001,
		OpCode_Jal = 5'b11011
	} OpCode;

	logic[31:0] in1;
	logic[31:0] in2;
	logic[31:0] in3;
	logic[31:0] in4;

	logic add_cin;
	wire[31:0] add_add;
	adder #(.width(32)) adder_module (
		.arg1(in1), .arg2(in2), .cin(add_cin),
		.add(add_add)
	);

	logic cmp_signed;
	wire cmp_lt;
	wire cmp_eq;
	cmp #(.width(32)) cmp_module (
		.arg1(in3), .arg2(in4), .cmp_signed(cmp_signed),
		.lt(cmp_lt), .eq(cmp_eq)
	);

	wire[31:0] logical_and;
	wire[31:0] logical_or;
	wire[31:0] logical_xor;
	logical #(.width(32)) logical_module (
		.arg1(in3), .arg2(in4),
		.out_and(logical_and), .out_or(logical_or), .out_xor(logical_xor)
	);

	logic shift_arithmetic;
	wire[31:0] shift_sll;
	wire[31:0] shift_sr;
	shift #(.width(32)) shift_module (
		.value(in3), .shamt(in4[0+:5]), .arithmetic(shift_arithmetic),
		.sll(shift_sll), .sr(shift_sr)
	);

	bit jump;
	assign pcnext_out = jump ? add_add[1+:31] : {pcnext_in, 1'b0};

	always_comb begin
		sigill = '0;

		rd = 'x;

		ram_load = '0;
		ram_store = '0;
		ram_funct3 = 'x;
		ram_address = 'x;
		ram_store_value = 'x;

		in1 = 'x;
		in2 = 'x;
		in3 = 'x;
		in4 = 'x;
		add_cin = 'x;
		cmp_signed = 'x;
		shift_arithmetic = 'x;

		jump = '0;

		unique case (OpCode'(opcode))
			// lb, lh, lw, lbu, lhu
			OpCode_Load:
				if (& funct3[0+:2] | & funct3[1+:2])
					sigill = '1;
				else begin
					in1 = rs1;
					in2 = imm;
					add_cin = '0;
					rd = ram_load_value;
					ram_load = '1;
					ram_funct3 = funct3;
					ram_address = add_add;
				end

			OpCode_OpImm: unique casez (funct3)
				// addi
				3'b000: begin
					in1 = rs1;
					in2 = imm;
					add_cin = '0;
					rd = add_add;
				end

				3'b001: unique case (imm[5+:7])
					// slli
					7'b0000000: begin
						in3 = rs1;
						in4 = {27'bx, imm[0+:5]};
						shift_arithmetic = imm[10];
						rd = shift_sll;
					end

					default: sigill = '1;
				endcase

				// slti, sltiu
				3'b01?: begin
					in3 = rs1;
					in4 = imm;
					cmp_signed = ~funct3[0];
					rd = 32'(cmp_lt);
				end

				// xori
				3'b100: begin
					in3 = rs1;
					in4 = imm;
					rd = logical_xor;
				end

				3'b101: unique casez (imm[5+:7])
					// srli, srai
					7'b0?00000: begin
						in3 = rs1;
						in4 = {27'bx, imm[0+:5]};
						shift_arithmetic = imm[10];
						rd = shift_sr;
					end

					default: sigill = '1;
				endcase

				// ori
				3'b110: begin
					in3 = rs1;
					in4 = imm;
					rd = logical_or;
				end

				// andi
				3'b111: begin
					in3 = rs1;
					in4 = imm;
					rd = logical_and;
				end
			endcase

			// auipc
			OpCode_Auipc: begin
				in1 = {pc, 2'b0};
				in2 = imm;
				add_cin = '0;
				rd = add_add;
			end

			// sb, sh, sw
			OpCode_Store:
				if (funct3[2] | & funct3[0+:2])
					sigill = '1;
				else begin
					in1 = rs1;
					in2 = imm;
					add_cin = '0;
					ram_store = '1;
					ram_funct3 = funct3;
					ram_address = add_add;
					ram_store_value = rs2;
				end

			OpCode_Op: unique casez ({funct3, funct7})
				// add, sub
				10'b000_0?00000: begin
					in1 = rs1;
					in2 = funct7[5] ? ~rs2 : rs2;
					add_cin = funct7[5];
					rd = add_add;
				end

				// sll
				10'b001_0000000: begin
					in3 = rs1;
					in4 = {27'bx, rs2[0+:5]};
					shift_arithmetic = funct7[5];
					rd = shift_sll;
				end

				// slt, sltu
				10'b01?_0000000: begin
					in3 = rs1;
					in4 = rs2;
					cmp_signed = ~funct3[0];
					rd = 32'(cmp_lt);
				end

				// xor
				10'b100_0000000: begin
					in3 = rs1;
					in4 = rs2;
					rd = logical_xor;
				end

				// srl, sra
				10'b101_0?00000: begin
					in3 = rs1;
					in4 = {27'bx, rs2[0+:5]};
					shift_arithmetic = funct7[5];
					rd = shift_sr;
				end

				// or
				10'b110_0000000: begin
					in3 = rs1;
					in4 = rs2;
					rd = logical_or;
				end

				// and
				10'b111_0000000: begin
					in3 = rs1;
					in4 = rs2;
					rd = logical_and;
				end

				default: sigill = '1;
			endcase

			// lui
			OpCode_Lui: begin
				rd = imm;
			end

			OpCode_Branch: unique casez (funct3)
				// beq, bne
				3'b00?: begin
					in1 = {pc, 2'b0};
					in2 = imm;
					add_cin = '0;
					in3 = rs1;
					in4 = rs2;
					jump = funct3[0] ^ cmp_eq;
				end

				3'b01?: sigill = '1;

				// blt, bge, bltu, bgeu
				3'b1??: begin
					in1 = {pc, 2'b0};
					in2 = imm;
					add_cin = '0;
					in3 = rs1;
					in4 = rs2;
					cmp_signed = ~funct3[1];
					jump = funct3[0] ^ cmp_lt;
				end
			endcase

			// jalr
			OpCode_Jalr: begin
				in1 = rs1;
				in2 = imm;
				add_cin = '0;
				rd = {pcnext_in, 2'b0};
				jump = '1;
			end

			// jal
			OpCode_Jal: begin
				in1 = {pc, 2'b0};
				in2 = imm;
				add_cin = '0;
				rd = {pcnext_in, 2'b0};
				jump = '1;
			end

			default: sigill = '1;
		endcase
	end
endmodule

module adder #(
	parameter width = 8
) (
	input bit[width - 1:0] arg1,
	input bit[width - 1:0] arg2,
	input bit cin,

	output bit[width - 1:0] add
);
	assign add = arg1 + arg2 + width'(cin);
endmodule

module cmp #(
	parameter width = 8
) (
	input bit[width - 1:0] arg1,
	input bit[width - 1:0] arg2,
	input bit cmp_signed,

	output bit lt,
	output bit eq
);
	function automatic void inner(
		input bit[width - 1:0] arg1,
		input bit[width - 1:0] arg2,
		input bit[$clog2(width) - 1:0] start_i,
		input bit[$clog2(width) - 1:0] end_i,
		input bit cmp_signed,

		output bit lt,
		output bit eq
	);
		if (start_i == end_i) begin
			lt = ~((cmp_signed ? arg2[start_i] : arg1[start_i]) | ~(arg1[start_i] | arg2[start_i]));
			eq = (arg1[start_i] & arg2[start_i]) | ~(arg1[start_i] | arg2[start_i]);

		end else begin
			bit lo_lt;
			bit lo_eq;

			bit hi_lt;
			bit hi_eq;

			inner(arg1, arg2, start_i, (start_i + end_i - 1) / 2, '0, lo_lt, lo_eq);
			inner(arg1, arg2, (start_i + end_i + 1 ) / 2, end_i, cmp_signed, hi_lt, hi_eq);

			lt = hi_lt | (hi_eq & lo_lt);
			eq = hi_eq & lo_eq;
		end
	endfunction

	always_comb
		inner(arg1, arg2, 0, width - 1, cmp_signed, lt, eq);
endmodule

module logical #(
	parameter width = 8
) (
	input bit[width - 1:0] arg1,
	input bit[width - 1:0] arg2,

	output bit[width - 1:0] out_and,
	output bit[width - 1:0] out_or,
	output bit[width - 1:0] out_xor
);
	assign out_and = arg1 & arg2;
	assign out_or = arg1 | arg2;
	assign out_xor = ~(out_and | ~out_or);
endmodule

module shift #(
	parameter width = 8
) (
	input bit[width - 1:0] value,
	input bit[$clog2(width) - 1:0] shamt,
	input bit arithmetic,

	output bit[width - 1:0] sll,
	output bit[width - 1:0] sr
);
	always_comb begin
		sll = value;
		sr = value;

		foreach (shamt[i])
			if (shamt[i]) begin
				sll = {sll[0+:width - (1 << i)], (1 << i)'('0)};
				sr = {{(1 << i){value[width - 1] & arithmetic}}, sr[1 << i+:width - (1 << i)]};
			end
	end
endmodule
