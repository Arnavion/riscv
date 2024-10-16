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
| mul/mulw rd, rs1, rs2           | 12/14  | 0      | 1      |        | -> | rs1/rs1w      | rs2/rs2w    | *l                |
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
	input logic[63:0] rs1,
	input logic[63:0] rs2,
	input logic[63:0] imm,
	input logic[63:0] csrimm,
	input bit[63:0] pc,
	input bit[63:0] pcnext_in,
	input logic[63:0] ram_load_value,
	input logic[63:0] csr_load_value,

	output bit sigill,
	output bit[63:0] pcnext_out,
	output logic[63:0] rd,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[63:0] ram_address,
	output logic[63:0] csr_store_value
);
	typedef enum bit[4:0] {
		OpCode_Load = 5'b00000,
		OpCode_OpImm = 5'b00100,
		OpCode_Auipc = 5'b00101,
		OpCode_OpImm32 = 5'b00110,
		OpCode_Store = 5'b01000,
		OpCode_Op = 5'b01100,
		OpCode_Lui = 5'b01101,
		OpCode_Op32 = 5'b01110,
		OpCode_Branch = 5'b11000,
		OpCode_Jalr = 5'b11001,
		OpCode_Jal = 5'b11011,
		OpCode_System = 5'b11100
	} OpCode;

	wire[63:0] rs1_sh1 = {rs1[0+:63], 1'b0};

	wire[63:0] rs1_sh2 = {rs1[0+:62], 2'b0};

	wire[63:0] rs1_sh3 = {rs1[0+:61], 3'b0};

	wire[63:0] rs1uw = {32'b0, rs1[0+:32]};

	wire[63:0] rs1uw_sh1 = {rs1uw[0+:63], 1'b0};

	wire[63:0] rs1uw_sh2 = {rs1uw[0+:62], 2'b0};

	wire[63:0] rs1uw_sh3 = {rs1uw[0+:61], 3'b0};

	wire[63:0] rs1w = {{32{rs1[31]}}, rs1[0+:32]};

	wire[63:0] rs2_decoded = 64'b1 << rs2[0+:6];

	wire[63:0] imm_decoded = 64'b1 << imm[0+:6];

	logic[63:0] in1;
	logic[63:0] in2;
	logic[63:0] in3;
	logic[63:0] in4;

	logic adder_cin;
	wire[63:0] adder_add;
	wire[63:0] adder_addw;
	adder adder_module (in1, in2, adder_cin, adder_add, adder_addw);

	logic cmp_signed;
	wire cmp_out_lt;
	wire cmp_out_eq;
	wire cmp_out_ne;
	wire cmp_out_ge;
	cmp cmp_module (in3, in4, cmp_signed, cmp_out_lt, cmp_out_eq, cmp_out_ne, cmp_out_ge);

	wire[63:0] logical_and;
	wire[63:0] logical_or;
	wire[63:0] logical_xor;
	logical logical_module (in3, in4, logical_and, logical_or, logical_xor);

	wire[63:0] shift_sll;
	wire[63:0] shift_sllw;
	wire[63:0] shift_srl;
	wire[63:0] shift_sra;
	shift shift_module (in3, in4[0+:6], shift_sll, shift_sllw, shift_srl, shift_sra);

	always_comb begin
		sigill = '0;

		pcnext_out = pcnext_in;

		rd = 'x;

		ram_load = '0;
		ram_store = '0;
		ram_address = 'x;
		ram_funct3 = 'x;

		csr_store_value = 'x;

		in1 = 'x;
		in2 = 'x;
		in3 = 'x;
		in4 = 'x;
		adder_cin = '0;
		cmp_signed = 'x;

		unique case (opcode)
			OpCode_Load: unique case (funct3)
				3'b000, // lb
				3'b001, // lh
				3'b010, // lw
				3'b011, // ld
				3'b100, // lbu
				3'b101, // lhu
				3'b110: // lwu
					begin
						in1 = rs1;
						in2 = imm;
						rd = ram_load_value;
						ram_load = '1;
						ram_funct3 = funct3;
						ram_address = adder_add;
					end

				default: sigill = '1;
			endcase

			OpCode_OpImm: unique case (funct3)
				// addi
				3'b000: begin
					in1 = rs1;
					in2 = imm;
					rd = adder_add;
				end

				3'b001: unique case (imm[6+:6])
					// slli
					6'b000000: begin
						in3 = rs1;
						in4 = {58'b0, imm[0+:6]};
						rd = shift_sll;
					end

					// bseti
					6'b001010: begin
						in3 = rs1;
						in4 = imm_decoded;
						rd = logical_or;
					end

					// bclri
					6'b010010: begin
						in3 = rs1;
						in4 = ~imm_decoded;
						rd = logical_and;
					end

					// binvi
					6'b011010: begin
						in3 = rs1;
						in4 = imm_decoded;
						rd = logical_xor;
					end

					default: sigill = '1;
				endcase

				// slti
				3'b010: begin
					in3 = rs1;
					in4 = imm;
					cmp_signed = '1;
					rd = {63'b0, cmp_out_lt};
				end

				// sltiu
				3'b011: begin
					in3 = rs1;
					in4 = imm;
					cmp_signed = '0;
					rd = {63'b0, cmp_out_lt};
				end

				// xori
				3'b100: begin
					in3 = rs1;
					in4 = imm;
					rd = logical_xor;
				end

				3'b101: unique case (imm[6+:6])
					// srli
					6'b000000: begin
						in3 = rs1;
						in4 = {58'b0, imm[0+:6]};
						rd = shift_srl;
					end

					// srai
					6'b010000: begin
						in3 = rs1;
						in4 = {58'b0, imm[0+:6]};
						rd = shift_sra;
					end

					// bexti
					6'b010010: begin
						in3 = rs1;
						in4 = imm;
						rd = {63'b0, shift_srl[0]};
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

				default: sigill = '1;
			endcase

			// auipc
			OpCode_Auipc: begin
				in1 = pc;
				in2 = imm;
				rd = adder_add;
			end

			OpCode_OpImm32: unique case (funct3)
				// addiw
				3'b000: begin
					in1 = rs1;
					in2 = imm;
					rd = adder_addw;
				end

				3'b001: unique casez (imm[5+:7])
					// slliw
					7'b0000000: begin
						in3 = rs1;
						in4 = {59'b0, imm[0+:5]};
						rd = shift_sllw;
					end

					// slli.uw
					7'b000010?: begin
						in3 = rs1uw;
						in4 = {58'b0, imm[0+:6]};
						rd = shift_sll;
					end

					default: sigill = '1;
				endcase

				3'b101: unique case (imm[5+:7])
					// srliw
					7'b0000000: begin
						in3 = rs1uw;
						in4 = {59'b0, imm[0+:5]};
						rd = shift_srl;
					end

					// sraiw
					7'b0100000: begin
						in3 = rs1w;
						in4 = {59'b0, imm[0+:5]};
						rd = shift_sra;
					end

					default: sigill = '1;
				endcase

				default: sigill = '1;
			endcase

			OpCode_Store: unique case (funct3)
				3'b000, // sb
				3'b001, // sh
				3'b010, // sw
				3'b011: // sd
					begin
						in1 = rs1;
						in2 = imm;
						ram_store = '1;
						ram_address = adder_add;
						ram_funct3 = funct3;
					end

				default: sigill = '1;
			endcase

			OpCode_Op: unique case ({funct3, funct7})
				// add
				10'b000_0000000: begin
					in1 = rs1;
					in2 = rs2;
					rd = adder_add;
				end

				// sub
				10'b000_0100000: begin
					in1 = rs1;
					in2 = ~rs2;
					adder_cin = '1;
					rd = adder_add;
				end

				// sll
				10'b001_0000000: begin
					in3 = rs1;
					in4 = {58'b0, rs2[0+:6]};
					rd = shift_sll;
				end

				// bset
				10'b001_0010100: begin
					in3 = rs1;
					in4 = rs2_decoded;
					rd = logical_or;
				end

				// bclr
				10'b001_0100100: begin
					in3 = rs1;
					in4 = ~rs2_decoded;
					rd = logical_and;
				end

				// binv
				10'b001_0110100: begin
					in3 = rs1;
					in4 = rs2_decoded;
					rd = logical_xor;
				end

				// slt
				10'b010_0000000: begin
					in3 = rs1;
					in4 = rs2;
					cmp_signed = '1;
					rd = {63'b0, cmp_out_lt};
				end

				// sh1add
				10'b010_0010000: begin
					in1 = rs1_sh1;
					in2 = rs2;
					rd = adder_add;
				end

				// sltu
				10'b011_0000000: begin
					in3 = rs1;
					in4 = rs2;
					cmp_signed = '0;
					rd = {63'b0, cmp_out_lt};
				end

				// xor
				10'b100_0000000: begin
					in3 = rs1;
					in4 = rs2;
					rd = logical_xor;
				end

				// sh2add
				10'b100_0010000: begin
					in1 = rs1_sh2;
					in2 = rs2;
					rd = adder_add;
				end

				// srl
				10'b101_0000000: begin
					in3 = rs1;
					in4 = {58'b0, rs2[0+:6]};
					rd = shift_srl;
				end

				// czero.eqz
				10'b101_0000111: begin
					in3 = '0;
					in4 = rs2;
					rd = cmp_out_eq ? '0 : rs1;
				end

				// sra
				10'b101_0100000: begin
					in3 = rs1;
					in4 = {58'b0, rs2[0+:6]};
					rd = shift_sra;
				end

				// bext
				10'b101_0110100: begin
					in3 = rs1;
					in4 = rs2;
					rd = {63'b0, shift_srl[0]};
				end

				// or
				10'b110_0000000: begin
					in3 = rs1;
					in4 = rs2;
					rd = logical_or;
				end

				// sh3add
				10'b110_0010000: begin
					in1 = rs1_sh3;
					in2 = rs2;
					rd = adder_add;
				end

				// and
				10'b111_0000000: begin
					in3 = rs1;
					in4 = rs2;
					rd = logical_and;
				end

				// czero.nez
				10'b111_0000111: begin
					in3 = '0;
					in4 = rs2;
					rd = cmp_out_ne ? '0 : rs1;
				end

				default: sigill = '1;
			endcase

			// lui
			OpCode_Lui: begin
				rd = imm;
			end

			OpCode_Op32: unique case ({funct3, funct7})
				// addw
				10'b000_0000000: begin
					in1 = rs1;
					in2 = rs2;
					rd = adder_addw;
				end

				// add.uw
				10'b000_0000100: begin
					in1 = rs1uw;
					in2 = rs2;
					rd = adder_addw;
				end

				// subw
				10'b000_0100000: begin
					in1 = rs1;
					in2 = ~rs2;
					adder_cin = '1;
					rd = adder_addw;
				end

				// sllw
				10'b001_0000000: begin
					in3 = rs1;
					in4 = {59'b0, rs2[0+:5]};
					rd = shift_sllw;
				end

				// sh1add.uw
				10'b010_0010000: begin
					in1 = rs1uw_sh1;
					in2 = rs2;
					rd = adder_addw;
				end

				// sh2add.uw
				10'b100_0010000: begin
					in1 = rs1uw_sh2;
					in2 = rs2;
					rd = adder_addw;
				end

				// srlw
				10'b101_0000000: begin
					in3 = rs1uw;
					in4 = {59'b0, rs2[0+:5]};
					rd = shift_srl;
				end

				// sraw
				10'b101_0100000: begin
					in3 = rs1w;
					in4 = {59'b0, rs2[0+:5]};
					rd = shift_sra;
				end

				// sh3add.uw
				10'b110_0010000: begin
					in1 = rs1uw_sh3;
					in2 = rs2;
					rd = adder_addw;
				end

				default: sigill = '1;
			endcase

			OpCode_Branch: unique case (funct3)
				// beq
				3'b000: begin
					in1 = pc;
					in2 = imm;
					in3 = rs1;
					in4 = rs2;
					if (cmp_out_eq)
						pcnext_out = adder_add;
				end

				// bne
				3'b001: begin
					in1 = pc;
					in2 = imm;
					in3 = rs1;
					in4 = rs2;
					if (cmp_out_ne)
						pcnext_out = adder_add;
				end

				// blt
				3'b100: begin
					in1 = pc;
					in2 = imm;
					in3 = rs1;
					in4 = rs2;
					cmp_signed = '1;
					if (cmp_out_lt)
						pcnext_out = adder_add;
				end

				// bge
				3'b101: begin
					in1 = pc;
					in2 = imm;
					in3 = rs1;
					in4 = rs2;
					cmp_signed = '1;
					if (cmp_out_ge)
						pcnext_out = adder_add;
				end

				// bltu
				3'b110: begin
					in1 = pc;
					in2 = imm;
					in3 = rs1;
					in4 = rs2;
					cmp_signed = '0;
					if (cmp_out_lt)
						pcnext_out = adder_add;
				end

				// bgeu
				3'b111: begin
					in1 = pc;
					in2 = imm;
					in3 = rs1;
					in4 = rs2;
					cmp_signed = '0;
					if (cmp_out_ge)
						pcnext_out = adder_add;
				end

				default: sigill = '1;
			endcase

			// jalr
			OpCode_Jalr: begin
				in1 = rs1;
				in2 = imm;
				rd = pcnext_in;
				pcnext_out = adder_add;
			end

			// jal
			OpCode_Jal: begin
				in1 = pc;
				in2 = imm;
				rd = pcnext_in;
				pcnext_out = adder_add;
			end

			OpCode_System: unique case (funct3)
				// csrrw
				3'b001: begin
					rd = csr_load_value;
					csr_store_value = rs1;
				end

				// csrrs
				3'b010: begin
					in3 = csr_load_value;
					in4 = rs1;
					rd = csr_load_value;
					csr_store_value = logical_or;
				end

				// csrrc
				3'b011: begin
					in3 = csr_load_value;
					in4 = ~rs1;
					rd = csr_load_value;
					csr_store_value = logical_and;
				end

				// csrrwi
				3'b101: begin
					rd = csr_load_value;
					csr_store_value = csrimm;
				end

				// csrrsi
				3'b110: begin
					in3 = csr_load_value;
					in4 = csrimm;
					rd = csr_load_value;
					csr_store_value = logical_or;
				end

				// csrrci
				3'b111: begin
					in3 = csr_load_value;
					in4 = ~csrimm;
					rd = csr_load_value;
					csr_store_value = logical_and;
				end

				default: sigill = '1;
			endcase

			default: sigill = '1;
		endcase
	end
endmodule

module adder (
	input bit[63:0] arg1,
	input bit[63:0] arg2,
	input bit cin,

	output bit[63:0] sum,
	output bit[63:0] sumw
);
	assign sum = arg1 + arg2 + {63'b0, cin};
	assign sumw = {{32{sum[31]}}, sum[0+:32]};
endmodule

module cmp (
	input bit[63:0] arg1,
	input bit[63:0] arg2,
	input bit cmp_signed,

	output bit lt,
	output bit eq,
	output bit ne,
	output bit ge
);
	assign lt = cmp_signed ? (signed'(arg1) < signed'(arg2)) : (unsigned'(arg1) < unsigned'(arg2));
	assign eq = arg1 == arg2;
	assign ne = ~eq;
	assign ge = ~lt;
endmodule

module logical (
	input bit[63:0] arg1,
	input bit[63:0] arg2,

	output bit[63:0] out_and,
	output bit[63:0] out_or,
	output bit[63:0] out_xor
);
	assign out_and = arg1 & arg2;
	assign out_or = arg1 | arg2;
	assign out_xor = arg1 ^ arg2;
endmodule

module shift (
	input bit[63:0] value,
	input bit[5:0] shamt,

	output bit[63:0] sll,
	output bit[63:0] sllw,
	output bit[63:0] srl,
	output bit[63:0] sra
);
	assign sll = value << shamt;
	assign sllw = {{32{sll[31]}}, sll[0+:32]};
	assign srl = value >> shamt;
	assign sra = unsigned'((signed'(value)) >>> shamt);
endmodule
