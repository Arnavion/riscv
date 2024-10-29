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

---

Zarnavion (produced by MOP fusion)

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-------------------+------+-------+---------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |        rd         | RAM  |  RAM  |   RAM   |
|                                 |        |        |        |        | -> |        in1        | in2  |                   | Load | Store | Address |
+=================================+========+========+========+========+====+===================+======+===================+======+=======+=========+
| lb.pc rd, imm(pc)               | 2      | 0      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
| lh.pc rd, imm(pc)               | 2      | 1      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
| lw.pc rd, imm(pc)               | 2      | 2      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
| ld.pc rd, imm(pc)               | 2      | 3      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
| lbu.pc rd, imm(pc)              | 2      | 4      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
| lhu.pc rd, imm(pc)              | 2      | 5      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
| lwu.pc rd, imm(pc)              | 2      | 6      | 0      |        | -> | pc                | imm  | RAM Load Value    | 1    |       | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+
| lb.add rd, rs2(rs1)             | 2      | 0      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
| lh.add rd, rs2(rs1)             | 2      | 1      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
| lw.add rd, rs2(rs1)             | 2      | 2      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
| ld.add rd, rs2(rs1)             | 2      | 3      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
| lbu.add rd, rs2(rs1)            | 2      | 4      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
| lhu.add rd, rs2(rs1)            | 2      | 5      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
| lwu.add rd, rs2(rs1)            | 2      | 6      | 1      |        | -> | rs1               | rs2  | RAM Load Value    | 1    |       | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+
| lb.sh1add rd, (rs1 << 1 + rs2)  | 2      | 0      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
| lh.sh1add rd, (rs1 << 1 + rs2)  | 2      | 1      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
| lw.sh1add rd, (rs1 << 1 + rs2)  | 2      | 2      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
| ld.sh1add rd, (rs1 << 1 + rs2)  | 2      | 3      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
| lbu.sh1add rd, (rs1 << 1 + rs2) | 2      | 4      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
| lhu.sh1add rd, (rs1 << 1 + rs2) | 2      | 5      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
| lwu.sh1add rd, (rs1 << 1 + rs2) | 2      | 6      | 2      |        | -> | rs1 << 1          | rs2  | RAM Load Value    | 1    |       | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+
| lb.sh2add rd, (rs1 << 2 + rs2)  | 2      | 0      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
| lh.sh2add rd, (rs1 << 2 + rs2)  | 2      | 1      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
| lw.sh2add rd, (rs1 << 2 + rs2)  | 2      | 2      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
| ld.sh2add rd, (rs1 << 2 + rs2)  | 2      | 3      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
| lbu.sh2add rd, (rs1 << 2 + rs2) | 2      | 4      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
| lhu.sh2add rd, (rs1 << 2 + rs2) | 2      | 5      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
| lwu.sh2add rd, (rs1 << 2 + rs2) | 2      | 6      | 3      |        | -> | rs1 << 2          | rs2  | RAM Load Value    | 1    |       | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+
| lb.sh3add rd, (rs1 << 3 + rs2)  | 2      | 0      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
| lh.sh3add rd, (rs1 << 3 + rs2)  | 2      | 1      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
| lw.sh3add rd, (rs1 << 3 + rs2)  | 2      | 2      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
| ld.sh3add rd, (rs1 << 3 + rs2)  | 2      | 3      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
| lbu.sh3add rd, (rs1 << 3 + rs2) | 2      | 4      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
| lhu.sh3add rd, (rs1 << 3 + rs2) | 2      | 5      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
| lwu.sh3add rd, (rs1 << 3 + rs2) | 2      | 6      | 4      |        | -> | rs1 << 3          | rs2  | RAM Load Value    | 1    |       | +       |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-------------------+------+-------+---------+

+---------------------------------+--------+--------+--------+--------+----+--------------------------+---------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |           Misc            |        rd         |
|                                 |        |        |        |        | -> |        in1        | in2  |     in3     |     in4     |                   |
+=================================+========+========+========+========+====+===================+======+=============+=============+===================+
| abs rd, rs1                     | 2      | 7      | 0      |        | -> | -rs1              | 0    | rs1         | +           | <s ? + : rs1      |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+---------------------------+-------------------+

 */

module rv_alu (
	input bit[4:0] opcode,
	input bit[2:0] funct3,
	input bit[6:0] funct7,
	input bit[4:0] funct5,
	input logic[63:0] rs1,
	input logic[63:0] rs2,
	input logic[63:0] imm,
	input logic[63:0] csrimm,
	input bit[63:0] pc,
	input bit[63:0] pcnext_in,
	input logic[63:0] ram_load_value,
	input logic[63:0] csr_load_value,
	input logic rd_is_x0,
	input logic rs1_is_x0,

	output bit sigill,
	output bit[63:0] pcnext_out,
	output logic[63:0] rd,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[63:0] ram_address,
	output bit csr_load,
	output bit csr_store,
	output logic[63:0] csr_store_value
);
	wire[63:0] rs1_sh1 = {rs1[0+:63], 1'b0};

	wire[63:0] rs1_sh2 = {rs1[0+:62], 2'b0};

	wire[63:0] rs1_sh3 = {rs1[0+:61], 3'b0};

	wire[63:0] rs1sb = {{56{rs1[7]}}, rs1[0+:8]};

	wire[63:0] rs1sh = {{48{rs1[15]}}, rs1[0+:16]};

	wire[63:0] rs1uh = {48'b0, rs1[0+:16]};

	wire[63:0] rs1uw = {32'b0, rs1[0+:32]};

	wire[63:0] rs1uw_sh1 = {rs1uw[0+:63], 1'b0};

	wire[63:0] rs1uw_sh2 = {rs1uw[0+:62], 2'b0};

	wire[63:0] rs1uw_sh3 = {rs1uw[0+:61], 3'b0};

	wire[63:0] rs1w = {{32{rs1[31]}}, rs1[0+:32]};

	wire[63:0] rs1_rev8_b;
	rev8_b rs1_rev8_b_module (rs1, rs1_rev8_b);

	wire[63:0] rs1uw_rev8_b;
	rev8_b rs1uw_rev8_b_module (rs1uw, rs1uw_rev8_b);

	wire[63:0] rs2_decoded = 64'b1 << rs2[0+:6];

	wire[63:0] imm_decoded = 64'b1 << imm[0+:6];

	logic[63:0] in1;
	logic[63:0] in2;
	logic[63:0] in3;
	logic[63:0] in4;
	logic[63:0] in5;

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

	wire[63:0] rotate_rol;
	wire[63:0] rotate_rolw;
	wire[63:0] rotate_ror;
	wire[63:0] rotate_rorw;
	rotate rotate_module (in3, in4[0+:6], rotate_rol, rotate_rolw, rotate_ror, rotate_rorw);

	wire[63:0] popcnt_cpop;
	wire[63:0] popcnt_cpopw;
	popcnt popcnt_module (in5, popcnt_cpop, popcnt_cpopw);

	wire[63:0] rs1_orc_b;
	orc_b orc_b_module (rs1, rs1_orc_b);

	wire[63:0] rs1_rev8;
	rev8 rev8_module (rs1, rs1_rev8);

	always_comb begin
		sigill = '0;

		pcnext_out = pcnext_in;

		rd = 'x;

		ram_load = '0;
		ram_store = '0;
		ram_address = 'x;
		ram_funct3 = 'x;

		csr_load = '0;
		csr_store = '0;
		csr_store_value = 'x;

		in1 = 'x;
		in2 = 'x;
		in3 = 'x;
		in4 = 'x;
		in5 = 'x;
		adder_cin = '0;
		cmp_signed = 'x;

		unique casez ({ opcode, funct3, funct7, funct5 })
			// I

			// auipc
			{20'b00101_???_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				rd = adder_add;
			end

			// lui
			{20'b01101_???_???????_?????}: begin
				rd = imm;
			end

			// addi
			{20'b00100_000_???????_?????}: begin
				in1 = rs1;
				in2 = imm;
				rd = adder_add;
			end

			// addiw
			{20'b00110_000_???????_?????}: begin
				in1 = rs1;
				in2 = imm;
				rd = adder_addw;
			end

			// add
			{20'b01100_000_0000000_?????}: begin
				in1 = rs1;
				in2 = rs2;
				rd = adder_add;
			end

			// addw
			{20'b01110_000_0000000_?????}: begin
				in1 = rs1;
				in2 = rs2;
				rd = adder_addw;
			end

			// sub
			{20'b01100_000_0100000_?????}: begin
				in1 = rs1;
				in2 = ~rs2;
				adder_cin = '1;
				rd = adder_add;
			end

			// subw
			{20'b01110_000_0100000_?????}: begin
				in1 = rs1;
				in2 = ~rs2;
				adder_cin = '1;
				rd = adder_addw;
			end

			// slti
			{20'b00100_010_???????_?????}: begin
				in3 = rs1;
				in4 = imm;
				cmp_signed = '1;
				rd = {63'b0, cmp_out_lt};
			end

			// sltiu
			{20'b00100_011_???????_?????}: begin
				in3 = rs1;
				in4 = imm;
				cmp_signed = '0;
				rd = {63'b0, cmp_out_lt};
			end

			// xori
			{20'b00100_100_???????_?????}: begin
				in3 = rs1;
				in4 = imm;
				rd = logical_xor;
			end

			// ori
			{20'b00100_110_???????_?????}: begin
				in3 = rs1;
				in4 = imm;
				rd = logical_or;
			end

			// andi
			{20'b00100_111_???????_?????}: begin
				in3 = rs1;
				in4 = imm;
				rd = logical_and;
			end

			// slli
			{20'b00100_001_000000?_?????}: begin
				in3 = rs1;
				in4 = {58'b0, imm[0+:6]};
				rd = shift_sll;
			end

			// slliw
			{20'b00110_001_0000000_?????}: begin
				in3 = rs1;
				in4 = {59'b0, imm[0+:5]};
				rd = shift_sllw;
			end

			// sll
			{20'b01100_001_0000000_?????}: begin
				in3 = rs1;
				in4 = {58'b0, rs2[0+:6]};
				rd = shift_sll;
			end

			// sllw
			{20'b01110_001_0000000_?????}: begin
				in3 = rs1;
				in4 = {59'b0, rs2[0+:5]};
				rd = shift_sllw;
			end

			// slt
			{20'b01100_010_0000000_?????}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				rd = {63'b0, cmp_out_lt};
			end

			// sltu
			{20'b01100_011_0000000_?????}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				rd = {63'b0, cmp_out_lt};
			end

			// xor
			{20'b01100_100_0000000_?????}: begin
				in3 = rs1;
				in4 = rs2;
				rd = logical_xor;
			end

			// srli
			{20'b00100_101_000000?_?????}: begin
				in3 = rs1;
				in4 = {58'b0, imm[0+:6]};
				rd = shift_srl;
			end

			// srliw
			{20'b00110_101_0000000_?????}: begin
				in3 = rs1uw;
				in4 = {59'b0, imm[0+:5]};
				rd = shift_srl;
			end

			// srl
			{20'b01100_101_0000000_?????}: begin
				in3 = rs1;
				in4 = {58'b0, rs2[0+:6]};
				rd = shift_srl;
			end

			// srlw
			{20'b01110_101_0000000_?????}: begin
				in3 = rs1uw;
				in4 = {59'b0, rs2[0+:5]};
				rd = shift_srl;
			end

			// or
			{20'b01100_110_0000000_?????}: begin
				in3 = rs1;
				in4 = rs2;
				rd = logical_or;
			end

			// and
			{20'b01100_111_0000000_?????}: begin
				in3 = rs1;
				in4 = rs2;
				rd = logical_and;
			end

			// srai
			{20'b00100_101_010000?_?????}: begin
				in3 = rs1;
				in4 = {58'b0, imm[0+:6]};
				rd = shift_sra;
			end

			// sraiw
			{20'b00110_101_0100000_?????}: begin
				in3 = rs1w;
				in4 = {59'b0, imm[0+:5]};
				rd = shift_sra;
			end

			// sra
			{20'b01100_101_0100000_?????}: begin
				in3 = rs1;
				in4 = {58'b0, rs2[0+:6]};
				rd = shift_sra;
			end

			// sraw
			{20'b01110_101_0100000_?????}: begin
				in3 = rs1w;
				in4 = {59'b0, rs2[0+:5]};
				rd = shift_sra;
			end

			// jalr
			{20'b11001_???_???????_?????}: begin
				in1 = rs1;
				in2 = imm;
				rd = pcnext_in;
				pcnext_out = adder_add;
			end

			// jal
			{20'b11011_???_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				rd = pcnext_in;
				pcnext_out = adder_add;
			end

			// beq
			{20'b11000_000_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				if (cmp_out_eq)
					pcnext_out = adder_add;
			end

			// bne
			{20'b11000_001_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				if (cmp_out_ne)
					pcnext_out = adder_add;
			end

			// blt
			{20'b11000_100_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				if (cmp_out_lt)
					pcnext_out = adder_add;
			end

			// bge
			{20'b11000_101_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				if (cmp_out_ge)
					pcnext_out = adder_add;
			end

			// bltu
			{20'b11000_110_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				if (cmp_out_lt)
					pcnext_out = adder_add;
			end

			// bgeu
			{20'b11000_111_???????_?????}: begin
				in1 = pc;
				in2 = imm;
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				if (cmp_out_ge)
					pcnext_out = adder_add;
			end

			{20'b00000_000_???????_?????}, // lb
			{20'b00000_001_???????_?????}, // lh
			{20'b00000_010_???????_?????}, // lw
			{20'b00000_011_???????_?????}, // ld
			{20'b00000_100_???????_?????}, // lbu
			{20'b00000_101_???????_?????}, // lhu
			{20'b00000_110_???????_?????}  // lwu
			: begin
				in1 = rs1;
				in2 = imm;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			{20'b01000_000_???????_?????}, // sb
			{20'b01000_001_???????_?????}, // sh
			{20'b01000_010_???????_?????}, // sw
			{20'b01000_011_???????_?????}  // sd
			: begin
				in1 = rs1;
				in2 = imm;
				ram_store = '1;
				ram_address = adder_add;
				ram_funct3 = funct3;
			end


			// Zicond

			// czero.eqz
			{20'b01100_101_0000111_?????}: begin
				in3 = '0;
				in4 = rs2;
				rd = cmp_out_eq ? '0 : rs1;
			end

			// czero.nez
			{20'b01100_111_0000111_?????}: begin
				in3 = '0;
				in4 = rs2;
				rd = cmp_out_ne ? '0 : rs1;
			end


			// Zicsr

			// csrrw
			{20'b11100_001_???????_?????}: begin
				rd = csr_load_value;
				csr_load = ~rd_is_x0;
				csr_store = '1;
				csr_store_value = rs1;
			end

			// csrrs
			{20'b11100_010_???????_?????}: begin
				in3 = csr_load_value;
				in4 = rs1;
				rd = csr_load_value;
				csr_load = '1;
				csr_store = ~rs1_is_x0;
				csr_store_value = logical_or;
			end

			// csrrc
			{20'b11100_011_???????_?????}: begin
				in3 = csr_load_value;
				in4 = ~rs1;
				rd = csr_load_value;
				csr_load = '1;
				csr_store = ~rs1_is_x0;
				csr_store_value = logical_and;
			end

			// csrrwi
			{20'b11100_101_???????_?????}: begin
				rd = csr_load_value;
				csr_load = ~rd_is_x0;
				csr_store = '1;
				csr_store_value = csrimm;
			end

			// csrrsi
			{20'b11100_110_???????_?????}: begin
				in3 = csr_load_value;
				in4 = csrimm;
				rd = csr_load_value;
				csr_load = '1;
				csr_store = (csrimm != '0);
				csr_store_value = logical_or;
			end

			// csrrci
			{20'b11100_111_???????_?????}: begin
				in3 = csr_load_value;
				in4 = ~csrimm;
				rd = csr_load_value;
				csr_load = '1;
				csr_store = (csrimm != '0);
				csr_store_value = logical_and;
			end


			// Zba

			// add.uw
			{20'b01110_000_0000100_?????}: begin
				in1 = rs1uw;
				in2 = rs2;
				rd = adder_addw;
			end

			// sh1add
			{20'b01100_010_0010000_?????}: begin
				in1 = rs1_sh1;
				in2 = rs2;
				rd = adder_add;
			end

			// sh1add.uw
			{20'b01110_010_0010000_?????}: begin
				in1 = rs1uw_sh1;
				in2 = rs2;
				rd = adder_addw;
			end

			// sh2add
			{20'b01100_100_0010000_?????}: begin
				in1 = rs1_sh2;
				in2 = rs2;
				rd = adder_add;
			end

			// sh2add.uw
			{20'b01110_100_0010000_?????}: begin
				in1 = rs1uw_sh2;
				in2 = rs2;
				rd = adder_addw;
			end

			// sh3add
			{20'b01100_110_0010000_?????}: begin
				in1 = rs1_sh3;
				in2 = rs2;
				rd = adder_add;
			end

			// sh3add.uw
			{20'b01110_110_0010000_?????}: begin
				in1 = rs1uw_sh3;
				in2 = rs2;
				rd = adder_addw;
			end

			// slli.uw
			{20'b00110_001_000010?_?????}: begin
				in3 = rs1uw;
				in4 = {58'b0, imm[0+:6]};
				rd = shift_sll;
			end


			// Zbb

			// xnor
			{20'b01100_100_0100000_?????}: begin
				in3 = rs1;
				in4 = ~rs2;
				rd = logical_xor;
			end

			// orn
			{20'b01100_110_0100000_?????}: begin
				in3 = rs1;
				in4 = ~rs2;
				rd = logical_or;
			end

			// andn
			{20'b01100_111_0100000_?????}: begin
				in3 = rs1;
				in4 = ~rs2;
				rd = logical_and;
			end

			// clz
			{20'b00100_001_0110000_00000}: begin
				in1 = rs1_rev8_b;
				in2 = 64'(-1);
				in3 = adder_add;
				in4 = ~in1;
				in5 = logical_and;
				rd = popcnt_cpop;
			end

			// clzw
			{20'b00110_001_0110000_00000}: begin
				in1 = rs1uw_rev8_b;
				in2 = 64'(-1);
				in3 = adder_add;
				in4 = ~in1;
				in5 = logical_and;
				rd = popcnt_cpopw;
			end

			// ctz
			{20'b00100_001_0110000_00001}: begin
				in1 = rs1;
				in2 = 64'(-1);
				in3 = adder_add;
				in4 = ~in1;
				in5 = logical_and;
				rd = popcnt_cpop;
			end

			// ctzw
			{20'b00110_001_0110000_00001}: begin
				in1 = rs1uw;
				in2 = 64'(-1);
				in3 = adder_add;
				in4 = ~in1;
				in5 = logical_and;
				rd = popcnt_cpopw;
			end

			// cpop
			{20'b00100_001_0110000_00010}: begin
				in5 = rs1;
				rd = popcnt_cpop;
			end

			// cpopw
			{20'b00110_001_0110000_00010}: begin
				in5 = rs1uw;
				rd = popcnt_cpop;
			end

			// min
			{20'b01100_100_0000101_?????}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				rd = cmp_out_lt ? rs1 : rs2;
			end

			// minu
			{20'b01100_101_0000101_?????}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				rd = cmp_out_lt ? rs1 : rs2;
			end

			// max
			{20'b01100_110_0000101_?????}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '1;
				rd = cmp_out_lt ? rs2 : rs1;
			end

			// maxu
			{20'b01100_111_0000101_?????}: begin
				in3 = rs1;
				in4 = rs2;
				cmp_signed = '0;
				rd = cmp_out_lt ? rs2 : rs1;
			end

			// zext.h
			{20'b01110_100_0000100_00000}: begin
				rd = rs1uh;
			end

			// sext.b
			{20'b00100_001_0110000_00100}: begin
				rd = rs1sb;
			end

			// sext.h
			{20'b00100_001_0110000_00101}: begin
				rd = rs1sh;
			end

			// rol
			{20'b01100_001_0110000_?????}: begin
				in3 = rs1;
				in4 = {58'b0, rs2[0+:6]};
				rd = rotate_rol;
			end

			// rolw
			{20'b01110_001_0110000_?????}: begin
				in3 = {rs1uw[0+:32], rs1uw[0+:32]};
				in4 = {59'b0, rs2[0+:5]};
				rd = rotate_rolw;
			end

			// rori
			{20'b00100_101_011000?_?????}: begin
				in3 = rs1;
				in4 = {58'b0, imm[0+:6]};
				rd = rotate_ror;
			end

			// roriw
			{20'b00110_101_0110000_?????}: begin
				in3 = {rs1uw[0+:32], rs1uw[0+:32]};
				in4 = {59'b0, imm[0+:5]};
				rd = rotate_rorw;
			end

			// ror
			{20'b01100_101_0110000_?????}: begin
				in3 = rs1;
				in4 = {58'b0, rs2[0+:6]};
				rd = rotate_ror;
			end

			// rorw
			{20'b01110_101_0110000_?????}: begin
				in3 = {rs1uw[0+:32], rs1uw[0+:32]};
				in4 = {59'b0, rs2[0+:5]};
				rd = rotate_rorw;
			end

			// orc.b
			{20'b00100_101_0010100_00111}: begin
				rd = rs1_orc_b;
			end

			// rev8
			{20'b00100_101_0110101_11000}: begin
				rd = rs1_rev8;
			end


			// Zbs

			// bseti
			{20'b00100_001_001010?_?????}: begin
				in3 = rs1;
				in4 = imm_decoded;
				rd = logical_or;
			end

			// bset
			{20'b01100_001_0010100_?????}: begin
				in3 = rs1;
				in4 = rs2_decoded;
				rd = logical_or;
			end

			// bclri
			{20'b00100_001_010010?_?????}: begin
				in3 = rs1;
				in4 = ~imm_decoded;
				rd = logical_and;
			end

			// bclr
			{20'b01100_001_0100100_?????}: begin
				in3 = rs1;
				in4 = ~rs2_decoded;
				rd = logical_and;
			end

			// bexti
			{20'b00100_101_011010?_?????}: begin
				in3 = rs1;
				in4 = imm;
				rd = {63'b0, shift_srl[0]};
			end

			// bext
			{20'b01100_101_0110100_?????}: begin
				in3 = rs1;
				in4 = rs2;
				rd = {63'b0, shift_srl[0]};
			end

			// binvi
			{20'b00100_001_011010?_?????}: begin
				in3 = rs1;
				in4 = imm_decoded;
				rd = logical_xor;
			end

			// binv
			{20'b01100_001_0110100_?????}: begin
				in3 = rs1;
				in4 = rs2_decoded;
				rd = logical_xor;
			end


			// Zarnavion

			{20'b00010_000_0000000_?????}, // lb.pc
			{20'b00010_001_0000000_?????}, // lh.pc
			{20'b00010_010_0000000_?????}, // lw.pc
			{20'b00010_011_0000000_?????}, // ld.pc
			{20'b00010_100_0000000_?????}, // lbu.pc
			{20'b00010_101_0000000_?????}, // lhu.pc
			{20'b00010_110_0000000_?????}  // lwu.pc
			: begin
				in1 = pc;
				in2 = imm;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			{20'b00010_000_0000001_?????}, // lb.add
			{20'b00010_001_0000001_?????}, // lh.add
			{20'b00010_010_0000001_?????}, // lw.add
			{20'b00010_011_0000001_?????}, // ld.add
			{20'b00010_100_0000001_?????}, // lbu.add
			{20'b00010_101_0000001_?????}, // lhu.add
			{20'b00010_110_0000001_?????}  // lwu.add
			: begin
				in1 = rs1;
				in2 = rs2;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			{20'b00010_000_0000010_?????}, // lb.sh1add
			{20'b00010_001_0000010_?????}, // lh.sh1add
			{20'b00010_010_0000010_?????}, // lw.sh1add
			{20'b00010_011_0000010_?????}, // ld.sh1add
			{20'b00010_100_0000010_?????}, // lbu.sh1add
			{20'b00010_101_0000010_?????}, // lhu.sh1add
			{20'b00010_110_0000010_?????}  // lwu.sh1add
			: begin
				in1 = rs1_sh1;
				in2 = rs2;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			{20'b00010_000_0000011_?????}, // lb.sh2add
			{20'b00010_001_0000011_?????}, // lh.sh2add
			{20'b00010_010_0000011_?????}, // lw.sh2add
			{20'b00010_011_0000011_?????}, // ld.sh2add
			{20'b00010_100_0000011_?????}, // lbu.sh2add
			{20'b00010_101_0000011_?????}, // lhu.sh2add
			{20'b00010_110_0000011_?????}  // lwu.sh2add
			: begin
				in1 = rs1_sh2;
				in2 = rs2;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			{20'b00010_000_0000100_?????}, // lb.sh3add
			{20'b00010_001_0000100_?????}, // lh.sh3add
			{20'b00010_010_0000100_?????}, // lw.sh3add
			{20'b00010_011_0000100_?????}, // ld.sh3add
			{20'b00010_100_0000100_?????}, // lbu.sh3add
			{20'b00010_101_0000100_?????}, // lhu.sh3add
			{20'b00010_110_0000100_?????}  // lwu.sh3add
			: begin
				in1 = rs1_sh3;
				in2 = rs2;
				rd = ram_load_value;
				ram_load = '1;
				ram_funct3 = funct3;
				ram_address = adder_add;
			end

			// abs
			{20'b00010_111_0000000_?????}: begin
				in1 = ~rs1;
				in2 = '0;
				adder_cin = '1;
				in3 = rs1;
				in4 = adder_add;
				rd = cmp_out_lt ? adder_add : rs1;
			end


			default: begin
				sigill = '1;
			end
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

module rotate (
	input bit[63:0] value,
	input bit[5:0] shamt,

	output bit[63:0] rol,
	output bit[63:0] rolw,
	output bit[63:0] ror,
	output bit[63:0] rorw
);
	assign rol = (value << shamt) | (value >> (-shamt));
	assign rolw = {{32{rol[31]}}, rol[0+:32]};
	assign ror = (value >> shamt) | (value << (-shamt));
	assign rorw = {{32{ror[31]}}, ror[0+:32]};
endmodule

module popcnt (
	input bit[63:0] arg,

	output bit[63:0] cpop,
	output bit[63:0] cpopw
);
	bit[6:0] sum;
	always_comb begin
		sum = '0;
		for (int i = 0; i < 64; i = i + 1) begin
			sum = sum + {6'b0, arg[i]};
		end
		cpop = {57'b0, sum};
		cpopw = {58'b0, sum[6], sum[0+:5]};
	end
endmodule

module orc_b (
	input bit[63:0] arg,

	output bit[63:0] out
);
	always_comb begin
		for (int i = 0; i < 64; i = i + 8) begin
			out[i+:8] = arg[i+:8] == '0 ? '0 : 8'(-1);
		end
	end
endmodule

module rev8 (
	input bit[63:0] arg,

	output bit[63:0] out
);
	always_comb begin
		for (int i = 0; i < 64; i = i + 8) begin
			out[i+:8] = arg[(56 - i)+:8];
		end
	end
endmodule

module rev_b (
	input bit[63:0] arg,

	output bit[63:0] out
);
	always_comb begin
		for (int i = 0; i < 64; i = i + 8) begin
			for (int j = 0; j < 8; j = j + 1) begin
				out[i + j] = arg[i + 7 - j];
			end
		end
	end
endmodule

module rev8_b (
	input bit[63:0] arg,

	output bit[63:0] out
);
	always_comb begin
		for (int i = 0; i < 64; i = i + 1) begin
			out[i] = arg[63 - i];
		end
	end
endmodule
