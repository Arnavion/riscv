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

+---------------------------------+--------+--------+--------+--------+----+--------------------------+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |           Misc            |        rd         |
|                                 |        |        |        |        | -> |        in1        | in2  |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+===================+======+=============+=============+===================+
| auipc rd, imm                   | 5      |        |        |        | -> | pc                | imm  |             |             | +                 |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+
| lui rd, imm                     | 13     |        |        |        | -> |                   |      |             |             | imm               |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+
| addi/addiw rd, rs1, imm         | 4/6    | 0      |        |        | -> | rs1               | imm  |             |             | +/+w              |
| add/addw rd, rs1, rs2           | 12/14  | 0      | 0      |        | -> | rs1               | rs2  |             |             | +/+w              |
| sub/subw rd, rs1, rs2           | 12/14  | 0      | 32     |        | -> | rs1               | -rs2 |             |             | +/+w              |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+
| slti rd, rs1, imm               | 4      | 2      |        |        | -> |                   |      | rs1         | imm         | <s                |
| sltiu rd, rs1, imm              | 4      | 3      |        |        | -> |                   |      | rs1         | imm         | <u                |
| xori rd, rs1, imm               | 4      | 4      |        |        | -> |                   |      | rs1         | imm         | ^                 |
| ori rd, rs1, imm                | 4      | 6      |        |        | -> |                   |      | rs1         | imm         | |                 |
| andi rd, rs1, imm               | 4      | 7      |        |        | -> |                   |      | rs1         | imm         | &                 |
| slli/slliw rd, rs1, imm         | 4/6    | 1      | 0/1    |        | -> |                   |      | rs1         | imm         | <</<<w            |
| sll/sllw rd, rs1, rs2           | 12/14  | 1      | 0      |        | -> |                   |      | rs1         | rs2         | <</<<w            |
| slt rd, rs1, rs2                | 12     | 2      | 0      |        | -> |                   |      | rs1         | rs2         | <s                |
| sltu rd, rs1, rs2               | 12     | 3      | 0      |        | -> |                   |      | rs1         | rs2         | <u                |
| xor rd, rs1, rs2                | 12     | 4      | 0      |        | -> |                   |      | rs1         | rs2         | ^                 |
| srli/srliw rd, rs1, imm         | 4/6    | 5      | 0/1    |        | -> |                   |      | rs1/rs1uw   | imm         | >>l               |
| srl/srlw rd, rs1, rs2           | 12/14  | 5      | 0      |        | -> |                   |      | rs1/rs1uw   | rs2         | >>l               |
| or rd, rs1, rs2                 | 12     | 6      | 0      |        | -> |                   |      | rs1         | rs2         | |                 |
| and rd, rs1, rs2                | 12     | 7      | 0      |        | -> |                   |      | rs1         | rs2         | &                 |
| srai/sraiw rd, rs1, imm         | 4/6    | 5      | 32/33  |        | -> |                   |      | rs1/rs1w    | imm         | >>a               |
| sra/sraw rd, rs1, rs2           | 12/14  | 5      | 32     |        | -> |                   |      | rs1/rs1w    | rs2         | >>a               |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+

+---------------------------------+--------+--------+--------+--------+----+--------------------------+---------------------------+-------------------+--------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |           Misc            |        rd         | pcnext |
|                                 |        |        |        |        | -> |        in1        | in2  |     in3     |     in4     |                   | from + |
+=================================+========+========+========+========+====+===================+======+=============+=============+===================+========+
| jalr rd, imm(rs1)               | 25     |        |        |        | -> | rs1               | imm  |             |             | pcnext            | 1      |
| jal rd, imm                     | 27     |        |        |        | -> | pc                | imm  |             |             | pcnext            | 1      |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+--------+
| beq rs1, rs2, imm               | 24     | 0      |        |        | -> | pc                | imm  | rs1         | rs2         |                   | =      |
| bne rs1, rs2, imm               | 24     | 1      |        |        | -> | pc                | imm  | rs1         | rs2         |                   | !=     |
| blt rs1, rs2, imm               | 24     | 4      |        |        | -> | pc                | imm  | rs1         | rs2         |                   | <s     |
| bge rs1, rs2, imm               | 24     | 5      |        |        | -> | pc                | imm  | rs1         | rs2         |                   | !<s    |
| bltu rs1, rs2, imm              | 24     | 6      |        |        | -> | pc                | imm  | rs1         | rs2         |                   | <u     |
| bgeu rs1, rs2, imm              | 24     | 7      |        |        | -> | pc                | imm  | rs1         | rs2         |                   | !<u    |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+--------+

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

+---------------------------------+--------+--------+--------+--------+----+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |           Misc            |        rd         |
|                                 |        |        |        |        | -> |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+=============+=============+===================+
| czero.eqz rd, rs1, rs2          | 12     | 5      | 7      |        | -> |             | rs2         | = ? 0 : rs1       |
| czero.nez rd, rs1, rs2          | 12     | 7      | 7      |        | -> |             | rs2         | = ? rs1 : 0       |
+---------------------------------+--------+--------+--------+--------+----+-------------+-------------+-------------------+

---

Zicsr

+---------------------------------+--------+--------+--------+--------+----+---------------------------+-------------------+----------+-------------+-----------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |           Misc            |        rd         | CSR Load |  CSR Store  | CSR Store Value |
|                                 |        |        |        |        | -> |     in3     |     in4     |                   |          |             |                 |
+=================================+========+========+========+========+====+=============+=============+===================+==========+=============+=================+
| csrrw csr, rd, rs1              | 28     | 1      |        |        | -> |             |             | csr               | rd != x0 | 1           | rs1             |
| csrrs csr, rd, rs1              | 28     | 2      |        |        | -> | csr         | rs1         | csr               | 1        | rs1 != x0   | |               |
| csrrc csr, rd, rs1              | 28     | 3      |        |        | -> | csr         | ~rs1        | csr               | 1        | rs1 != x0   | &               |
| csrrwi csr, rd, csrimm          | 28     | 5      |        |        | -> |             |             | csr               | rd != x0 | 1           | csrimm          |
| csrrsi csr, rd, csrimm          | 28     | 6      |        |        | -> | csr         | csrimm      | csr               | 1        | csrimm != 0 | |               |
| csrrci csr, rd, csrimm          | 28     | 7      |        |        | -> | csr         | ~csrimm     | csr               | 1        | csrimm != 0 | &               |
+---------------------------------+--------+--------+--------+--------+----+-------------+-------------+-------------------+----------+-------------+-----------------+

---

Zba

+---------------------------------+--------+--------+--------+--------+----+--------------------------+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |           Misc            |        rd         |
|                                 |        |        |        |        | -> |        in1        | in2  |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+===================+======+=============+=============+===================+
| add.uw rd, rs1, rs2             | 14     | 0      | 4      |        | -> | rs1uw             | rs2  |             |             | +                 |
| sh1add/sh1add.uw rd, rs1, rs2   | 12/14  | 2      | 16     |        | -> | rs1/rs1uw << 1    | rs2  |             |             | +                 |
| sh2add/sh2add.uw rd, rs1, rs2   | 12/14  | 4      | 16     |        | -> | rs1/rs1uw << 2    | rs2  |             |             | +                 |
| sh3add/sh3add.uw rd, rs1, rs2   | 12/14  | 6      | 16     |        | -> | rs1/rs1uw << 3    | rs2  |             |             | +                 |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+
| slli.uw rd, rs1, imm            | 6      | 1      | 4/5    |        | -> |                   |      | rs1uw       | imm         | <<                |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+

---

Zbb

+---------------------------------+--------+--------+--------+--------+----+--------------------------+---------------------------+-------------------+-----------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |           Misc            |        rd         |   cpop    |
|                                 |        |        |        |        | -> |        in1        | in2  |     in3     |     in4     |                   |    in5    |
+=================================+========+========+========+========+====+===================+======+=============+=============+===================+===========+
| xnor rd, rs1, rs2               | 12     | 4      | 32     |        | -> |                   |      | rs1         | ~rs2        | ^                 |           |
| orn rd, rs1, rs2                | 12     | 6      | 32     |        | -> |                   |      | rs1         | ~rs2        | |                 |           |
| andn rd, rs1, rs2               | 12     | 7      | 32     |        | -> |                   |      | rs1         | ~rs2        | &                 |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+
| clz/clzw rd, rs1                | 4/6    | 1      | 48     | 0      | -> | rev8.b(rs1/rs1uw) | -1   | +           | ~in1        | cpop/cpopw        | &         |
| ctz/ctzw rs1                    | 4/6    | 1      | 48     | 1      | -> | rs1/rs1uw         | -1   | +           | ~in1        | cpop/cpopw        | &         |
| cpop/cpopw rd, rs1              | 4/6    | 1      | 48     | 2      | -> |                   |      |             |             | cpop              | rs1/rs1uw |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+
| min rd, rs1, rs2                | 12     | 4      | 5      |        | -> |                   |      | rs1         |  rs2        | <s ? rs1 : rs2    |           |
| minu rd, rs1, rs2               | 12     | 5      | 5      |        | -> |                   |      | rs1         |  rs2        | <u ? rs1 : rs2    |           |
| max rd, rs1, rs2                | 12     | 6      | 5      |        | -> |                   |      | rs1         |  rs2        | <s ? rs2 : rs1    |           |
| maxu rd, rs1, rs2               | 12     | 7      | 5      |        | -> |                   |      | rs1         |  rs2        | <u ? rs2 : rs1    |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+
| zext.h rd, rs1                  | 14     | 4      | 4      | 0      | -> |                   |      |             |             | rs1uh             |           |
| sext.b rd, rs1                  | 4      | 1      | 48     | 4      | -> |                   |      |             |             | rs1sb             |           |
| sext.h rd, rs1                  | 4      | 1      | 48     | 5      | -> |                   |      |             |             | rs1sh             |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+
| rol rd, rs1, rs2                | 12     | 1      | 48     |        | -> |                   |      | rs1         |  rs2        | rol               |           |
| rolw rd, rs1, rs2               | 14     | 1      | 48     |        | -> |                   |      | rs1uw:rs1uw |  rs2        | rolw              |           |
| rori rd, rs1, imm               | 4      | 5      | 48/49  |        | -> |                   |      | rs1         |  imm        | ror               |           |
| roriw rd, rs1, imm              | 6      | 5      | 48     |        | -> |                   |      | rs1uw:rs1uw |  imm        | rorw              |           |
| ror rd, rs1, rs2                | 12     | 5      | 48     |        | -> |                   |      | rs1         |  rs2        | ror               |           |
| rorw rd, rs1, rs2               | 14     | 5      | 48     |        | -> |                   |      | rs1uw:rs1uw |  rs2        | rorw              |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+
| orc.b rd, rs1                   | 4      | 5      | 20     | 7      | -> |                   |      |             |             | orc.b(rs1)        |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+
| rev8 rd, rs1                    | 4      | 5      | 53     | 24     | -> |                   |      |             |             | rev8(rs1)         |           |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------+-------------+-------------------+-----------+

---

Zbs

+---------------------------------+--------+--------+--------+--------+----+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |           Misc            |        rd         |
|                                 |        |        |        |        | -> |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+=============+=============+===================+
| bseti rd, rs1, imm              | 4      | 1      | 20/21  |        | -> | rs1         | 1 << imm    | |                 |
| bset rd, rs1, rs2               | 12     | 1      | 20     |        | -> | rs1         | 1 << rs2    | |                 |
| bclri rd, rs1, imm              | 4      | 1      | 36/37  |        | -> | rs1         | ~(1 << imm) | &                 |
| bclr rd, rs1, rs2               | 12     | 1      | 36     |        | -> | rs1         | ~(1 << rs2) | &                 |
| bexti rd, rs1, imm              | 4      | 5      | 36/37  |        | -> | rs1         | imm         | >> & 1            |
| bext rd, rs1, rs2               | 12     | 5      | 36     |        | -> | rs1         | rs2         | >> & 1            |
| binvi rd, rs1, imm              | 4      | 1      | 52/53  |        | -> | rs1         | 1 << imm    | ^                 |
| binv rd, rs1, rs2               | 12     | 1      | 52     |        | -> | rs1         | 1 << rs2    | ^                 |
+---------------------------------+--------+--------+--------+--------+----+-------------+-------------+-------------------+

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

+---------------------------------+--------+--------+--------+--------+----+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |           Misc            |        rd         |
|                                 |        |        |        |        | -> |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+=============+=============+===================+
| xperm.n rd, rs1, rs2            | 12     | 2      | 20     |        | -> | rs1         | rs2         | xperm.n(rs1, rs2) |
| xperm.b rd, rs1, rs2            | 12     | 4      | 20     |        | -> | rs1         | rs2         | xperm.b(rs1, rs2) |
+---------------------------------+--------+--------+--------+--------+----+-------------+-------------+-------------------+

---

Zmmul

+---------------------------------+--------+--------+--------+--------+----+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |           Misc            |        rd         |
|                                 |        |        |        |        | -> |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+=============+=============+===================+
| mul/mulw rd, rs1, rs2           | 12/14  | 0      | 1      |        | -> | rs1/rs1w    | rs2/rs2w    | *l                |
| mulh rd, rs1, rs2               | 12     | 1      | 1      |        | -> | rs1         | rs2         | *hss              |
| mulhsu rd, rs1, rs2             | 12     | 2      | 1      |        | -> | rs1         | rs2         | *hsu              |
| mulhu rd, rs1, rs2              | 12     | 3      | 1      |        | -> | rs1         | rs2         | *huu              |
+---------------------------------+--------+--------+--------+--------+----+-------------+-------------+-------------------+

---

M

+---------------------------------+--------+--------+--------+--------+----+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |           Misc            |        rd         |
|                                 |        |        |        |        | -> |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+=============+=============+===================+
| div rd, rs1, rs2                | 12     | 4      | 1      |        | -> | rs1         | rs2         | /                 |
| divw rd, rs1, rs2               | 14     | 4      | 1      |        | -> | rs1w        | rs2w        | /w                |
| divu rd, rs1, rs2               | 12     | 5      | 1      |        | -> | rs1         | rs2         | /u                |
| divuw rd, rs1, rs2              | 14     | 5      | 1      |        | -> | rs1uw       | rs2uw       | /uw               |
| rem rd, rs1, rs2                | 12     | 6      | 1      |        | -> | rs1         | rs2         | %                 |
| remw rd, rs1, rs2               | 14     | 6      | 1      |        | -> | rs1w        | rs2w        | %w                |
| remu rd, rs1, rs2               | 12     | 7      | 1      |        | -> | rs1         | rs2         | %u                |
| remuw rd, rs1, rs2              | 14     | 7      | 1      |        | -> | rs1uw       | rs2uw       | %uw               |
+---------------------------------+--------+--------+--------+--------+----+-------------+-------------+-------------------+

 */

module rv_alu (
	input bit[4:0] opcode,
	input bit[2:0] funct3,
	input bit[6:0] funct7,
	input logic[31:0] rs1,
	input logic[31:0] rs2,
	input logic[31:0] imm,
	input bit[31:0] pc,
	input bit[31:0] pcnext_in,
	input logic[31:0] ram_load_value,

	output bit sigill,
	output bit[31:0] pcnext_out,
	output logic[31:0] rd,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[31:0] ram_address
);
	logic[31:0] in1;
	logic[31:0] in2;
	logic[31:0] in3;
	logic[31:0] in4;

	logic adder_cin;
	wire[31:0] adder_add;
	adder adder_module (in1, in2, adder_cin, adder_add);

	logic cmp_signed;
	wire cmp_out_lt;
	wire cmp_out_eq;
	wire cmp_out_ne;
	wire cmp_out_ge;
	cmp cmp_module (in3, in4, cmp_signed, cmp_out_lt, cmp_out_eq, cmp_out_ne, cmp_out_ge);

	wire[31:0] logical_and;
	wire[31:0] logical_or;
	wire[31:0] logical_xor;
	logical logical_module (in3, in4, logical_and, logical_or, logical_xor);

	wire[31:0] shift_sll;
	wire[31:0] shift_srl;
	wire[31:0] shift_sra;
	shift shift_module (in3, in4[0+:5], shift_sll, shift_srl, shift_sra);

	always_comb begin
		sigill = '0;

		pcnext_out = pcnext_in;

		rd = 'x;

		ram_load = '0;
		ram_store = '0;
		ram_address = 'x;
		ram_funct3 = 'x;

		in1 = 'x;
		in2 = 'x;
		in3 = 'x;
		in4 = 'x;
		adder_cin = '0;
		cmp_signed = 'x;

		unique casez ({ opcode, funct3, funct7 })
			// I

			// auipc
			{15'b00101_???_???????}: begin
				in1 = pc;
				in2 = imm;
				rd = adder_add;
			end

			// lui
			{15'b01101_???_???????}: begin
				rd = imm;
			end

			// addi
			{15'b00100_000_???????}: begin
				in1 = rs1;
				in2 = imm;
				rd = adder_add;
			end

			// add
			{15'b01100_000_0000000}: begin
				in1 = rs1;
				in2 = rs2;
				rd = adder_add;
			end

			// sub
			{15'b01100_000_0100000}: begin
				in1 = rs1;
				in2 = ~rs2;
				adder_cin = '1;
				rd = adder_add;
			end

			// slti
			{15'b00100_010_???????}: begin
				in3 = rs1;
				in4 = imm;
				cmp_signed = '1;
				rd = {31'b0, cmp_out_lt};
			end

			// sltiu
			{15'b00100_011_???????}: begin
				in3 = rs1;
				in4 = imm;
				cmp_signed = '0;
				rd = {31'b0, cmp_out_lt};
			end

			// xori
			{15'b00100_100_???????}: begin
				in3 = rs1;
				in4 = imm;
				rd = logical_xor;
			end

			// ori
			{15'b00100_110_???????}: begin
				in3 = rs1;
				in4 = imm;
				rd = logical_or;
			end

			// andi
			{15'b00100_111_???????}: begin
				in3 = rs1;
				in4 = imm;
				rd = logical_and;
			end

			// slli
			{15'b00100_001_000000?}: begin
				in3 = rs1;
				in4 = {27'b0, imm[0+:5]};
				rd = shift_sll;
			end

			// sll
			{15'b01100_001_0000000}: begin
				in3 = rs1;
				in4 = {27'b0, rs2[0+:5]};
				rd = shift_sll;
			end

			// slt
			{15'b01100_010_0000000}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				rd = {31'b0, cmp_out_lt};
			end

			// sltu
			{15'b01100_011_0000000}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				rd = {31'b0, cmp_out_lt};
			end

			// xor
			{15'b01100_100_0000000}: begin
				in3 = rs1;
				in4 = rs2;
				rd = logical_xor;
			end

			// srli
			{15'b00100_101_000000?}: begin
				in3 = rs1;
				in4 = {27'b0, imm[0+:5]};
				rd = shift_srl;
			end

			// srl
			{15'b01100_101_0000000}: begin
				in3 = rs1;
				in4 = {27'b0, rs2[0+:5]};
				rd = shift_srl;
			end

			// or
			{15'b01100_110_0000000}: begin
				in3 = rs1;
				in4 = rs2;
				rd = logical_or;
			end

			// and
			{15'b01100_111_0000000}: begin
				in3 = rs1;
				in4 = rs2;
				rd = logical_and;
			end

			// srai
			{15'b00100_101_010000?}: begin
				in3 = rs1;
				in4 = {27'b0, imm[0+:5]};
				rd = shift_sra;
			end

			// sra
			{15'b01100_101_0100000}: begin
				in3 = rs1;
				in4 = {27'b0, rs2[0+:5]};
				rd = shift_sra;
			end

			// jalr
			{15'b11001_???_???????}: begin
				in1 = rs1;
				in2 = imm;
				rd = pcnext_in;
				pcnext_out = adder_add;
			end

			// jal
			{15'b11011_???_???????}: begin
				in1 = pc;
				in2 = imm;
				rd = pcnext_in;
				pcnext_out = adder_add;
			end

			// beq
			{15'b11000_000_???????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				if (cmp_out_eq)
					pcnext_out = adder_add;
			end

			// bne
			{15'b11000_001_???????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				if (cmp_out_ne)
					pcnext_out = adder_add;
			end

			// blt
			{15'b11000_100_???????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				if (cmp_out_lt)
					pcnext_out = adder_add;
			end

			// bge
			{15'b11000_101_???????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				if (cmp_out_ge)
					pcnext_out = adder_add;
			end

			// bltu
			{15'b11000_110_???????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				if (cmp_out_lt)
					pcnext_out = adder_add;
			end

			// bgeu
			{15'b11000_111_???????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				if (cmp_out_ge)
					pcnext_out = adder_add;
			end

			{15'b00000_000_???????}, // lb
			{15'b00000_001_???????}, // lh
			{15'b00000_010_???????}, // lw
			{15'b00000_011_???????}, // ld
			{15'b00000_100_???????}, // lbu
			{15'b00000_101_???????}, // lhu
			{15'b00000_110_???????}  // lwu
			: begin
				in1 = rs1;
				in2 = imm;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			{15'b01000_000_???????}, // sb
			{15'b01000_001_???????}, // sh
			{15'b01000_010_???????}, // sw
			{15'b01000_011_???????}  // sd
			: begin
				in1 = rs1;
				in2 = imm;
				ram_store = '1;
				ram_address = adder_add;
				ram_funct3 = funct3;
			end


			default: begin
				sigill = '1;
			end
		endcase
	end
endmodule

module adder (
	input bit[31:0] arg1,
	input bit[31:0] arg2,
	input bit cin,

	output bit[31:0] sum
);
	assign sum = arg1 + arg2 + {31'b0, cin};
endmodule

module cmp (
	input bit[31:0] arg1,
	input bit[31:0] arg2,
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
	input bit[31:0] arg1,
	input bit[31:0] arg2,

	output bit[31:0] out_and,
	output bit[31:0] out_or,
	output bit[31:0] out_xor
);
	assign out_and = arg1 & arg2;
	assign out_or = arg1 | arg2;
	assign out_xor = arg1 ^ arg2;
endmodule

module shift (
	input bit[31:0] value,
	input bit[4:0] shamt,

	output bit[31:0] sll,
	output bit[31:0] srl,
	output bit[31:0] sra
);
	assign sll = value << shamt;
	assign srl = value >> shamt;
	assign sra = unsigned'((signed'(value)) >>> shamt);
endmodule