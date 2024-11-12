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

+---------------------------------+--------+--------+--------+--------+----+--------------------------+-----------------------------+-------------------+
|              inst               | opcode | funct3 | funct7 | funct5 | -> |          Adder           |            Misc             |        rd         |
|                                 |        |        |        |        | -> |        in1        | in2  |      in3      |     in4     |                   |
+=================================+========+========+========+========+====+===================+======+===============+=============+===================+
| abs rd, rs1                     | 2      | 7      | 0      |        | -> | -rs1              | 0    | rs1           | +           | <s ? + : rs1      |
+---------------------------------+--------+--------+--------+--------+----+-------------------+------+-----------------------------+-------------------+

 */

module rv_alu (
	input bit[4:0] opcode,
	input bit[2:0] funct3,
	input bit[6:0] funct7,
	input bit[4:0] funct5,
	input logic[63:0] rs1,
	input logic[63:0] rs2,
	input logic[32:0] imm_,
	input logic[4:0] csrimm_,
	input bit[63:1] pc,
	input bit[63:1] pcnext_in,
	input logic[63:0] ram_load_value,
	input logic[63:0] csr_load_value,

	output bit sigill,
	output bit[63:1] pcnext_out,
	output logic[63:0] rd,
	output bit ram_load,
	output bit ram_store,
	output logic[2:0] ram_funct3,
	output logic[63:0] ram_address,
	output logic[63:0] ram_store_value,
	output logic[63:0] csr_store_value
);
	typedef enum bit[4:0] {
		OpCode_Load = 5'b00000,
		OpCode_Zarnavion = 5'b00010,
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

	wire[63:0] rs1sb = unsigned'(64'(signed'(rs1[0+:8])));

	wire[63:0] rs1sh = unsigned'(64'(signed'(rs1[0+:16])));

	wire[63:0] rs1uh = 64'(rs1[0+:16]);

	wire[63:0] rs1uw = 64'(rs1[0+:32]);

	wire[63:0] rs1uw_sh1 = {rs1uw[0+:63], 1'b0};

	wire[63:0] rs1uw_sh2 = {rs1uw[0+:62], 2'b0};

	wire[63:0] rs1uw_sh3 = {rs1uw[0+:61], 3'b0};

	wire[63:0] rs1w = unsigned'(64'(signed'(rs1[0+:32])));

	wire[63:0] imm = unsigned'(64'(signed'(imm_)));

	wire[63:0] csrimm = 64'(csrimm_);

	wire[63:0] rs1_rev8_b = {<<{rs1}};

	wire[63:0] rs2w = unsigned'(64'(signed'(rs2[0+:32])));

	wire[63:0] rs2_decoded = 64'b1 << rs2[0+:6];

	wire[63:0] imm_decoded = 64'b1 << imm[0+:6];

	logic[63:0] in1;
	logic[63:0] in2;
	logic[63:0] in3;
	logic[63:0] in4;
	logic[63:0] in5;

	logic add_cin;
	wire[63:0] add_add;
	wire[63:0] add_addw;
	adder #(.width(64)) adder_module (
		.arg1(in1), .arg2(in2), .cin(add_cin),
		.add(add_add), .addw(add_addw)
	);

	logic cmp_signed;
	wire cmp_lt;
	wire cmp_eq;
	cmp #(.width(64)) cmp_module (
		.arg1(in3), .arg2(in4), .cmp_signed(cmp_signed),
		.lt(cmp_lt), .eq(cmp_eq)
	);

	logic logical_invert_arg2;
	wire[63:0] logical_and;
	wire[63:0] logical_or;
	wire[63:0] logical_xor;
	logical #(.width(64)) logical_module (
		.arg1(in3), .arg2(in4), .invert_arg2(logical_invert_arg2),
		.out_and(logical_and), .out_or(logical_or), .out_xor(logical_xor)
	);

	logic mul_arg1_is_signed;
	logic mul_arg2_is_signed;
	wire[63:0] mul_mulw;
	wire[63:0] mul_mul;
	wire[63:0] mul_mulh;
	multiplier #(.width(64)) multiplier_module (
		.arg1(in3), .arg1_is_signed(mul_arg1_is_signed), .arg2(in4), .arg2_is_signed(mul_arg2_is_signed),
		.mulw(mul_mulw), .mul(mul_mul), .mulh(mul_mulh)
	);

	wire[63:0] rs1_orc_b;
	orc_b #(.width(64)) orc_b_module (
		.arg(rs1),
		.out(rs1_orc_b)
	);

	wire[63:0] popcnt_cpop;
	wire[63:0] popcnt_cpopw;
	popcnt #(.width(64)) popcnt_module (
		.arg(in5),
		.cpop(popcnt_cpop), .cpopw(popcnt_cpopw)
	);

	wire[63:0] rs1_rev8 = {<<8{rs1}};

	logic shift_rotate_right;
	logic shift_rotate_rotate;
	logic shift_rotate_arithmetic;
	logic shift_rotate_w;
	wire[63:0] shift_rotate_result;
	shift_rotate #(.width(64)) shift_rotate_module (
		.value(in3), .shamt(in4[0+:6]),
		.right(shift_rotate_right), .rotate(shift_rotate_rotate), .arithmetic(shift_rotate_arithmetic), .w(shift_rotate_w),
		.result(shift_rotate_result)
	);

	bit jump;
	assign pcnext_out = jump ? add_add[1+:63] : pcnext_in;

	always_comb begin
		sigill = '0;

		rd = 'x;

		ram_load = '0;
		ram_store = '0;
		ram_funct3 = 'x;
		ram_address = 'x;
		ram_store_value = 'x;

		csr_store_value = 'x;

		in1 = 'x;
		in2 = 'x;
		in3 = 'x;
		in4 = 'x;
		in5 = 'x;
		add_cin = 'x;
		cmp_signed = 'x;
		logical_invert_arg2 = 'x;
		mul_arg1_is_signed = 'x;
		mul_arg2_is_signed = 'x;
		shift_rotate_right = 'x;
		shift_rotate_rotate = 'x;
		shift_rotate_arithmetic = 'x;
		shift_rotate_w = 'x;

		jump = '0;

		unique case (OpCode'(opcode))
			// lb, lh, lw, ld, lbu, lhu, lwu
			OpCode_Load:
				if (& funct3[0+:3])
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

			OpCode_Zarnavion: unique casez ({funct3, funct7})
				// l*.pc
				10'b???_0000000:
					if (& funct3[0+:3])
						sigill = '1;
					else begin
						in1 = {pc, 1'b0};
						in2 = imm;
						add_cin = '0;
						rd = ram_load_value;
						ram_load = '1;
						ram_funct3 = funct3;
						ram_address = add_add;
					end

				// l*.add
				10'b???_0000001:
					if (& funct3[0+:3])
						sigill = '1;
					else begin
						in1 = rs1;
						in2 = rs2;
						add_cin = '0;
						rd = ram_load_value;
						ram_load = '1;
						ram_funct3 = funct3;
						ram_address = add_add;
					end

				// l*.sh1add
				10'b???_0000010:
					if (& funct3[0+:3])
						sigill = '1;
					else begin
						in1 = rs1_sh1;
						in2 = rs2;
						add_cin = '0;
						rd = ram_load_value;
						ram_load = '1;
						ram_funct3 = funct3;
						ram_address = add_add;
					end

				// l*.sh2add
				10'b???_0000011:
					if (& funct3[0+:3])
						sigill = '1;
					else begin
						in1 = rs1_sh2;
						in2 = rs2;
						add_cin = '0;
						rd = ram_load_value;
						ram_load = '1;
						ram_funct3 = funct3;
						ram_address = add_add;
					end

				// l*.sh3add
				10'b???_0000100:
					if (& funct3[0+:3])
						sigill = '1;
					else begin
						in1 = rs1_sh3;
						in2 = rs2;
						add_cin = '0;
						rd = ram_load_value;
						ram_load = '1;
						ram_funct3 = funct3;
						ram_address = add_add;
					end

				// abs
				10'b000_0000101: begin
					in1 = ~rs1;
					in2 = '0;
					add_cin = '1;
					rd = rs1[63] ? add_add : rs1;
				end

				default: sigill = '1;
			endcase

			OpCode_OpImm: unique casez (funct3)
				// addi
				3'b000: begin
					in1 = rs1;
					in2 = imm;
					add_cin = '0;
					rd = add_add;
				end

				3'b001: unique case (imm[6+:6])
					// slli
					6'b000000: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_arithmetic = imm[10];
						shift_rotate_w = opcode[1];
						rd = shift_rotate_result;
					end

					// bseti
					6'b001010: begin
						in3 = rs1;
						in4 = imm_decoded;
						logical_invert_arg2 = '0;
						rd = logical_or;
					end

					// bclri
					6'b010010: begin
						in3 = rs1;
						in4 = imm_decoded;
						logical_invert_arg2 = '1;
						rd = logical_and;
					end

					6'b011000: unique case (imm[0+:6])
						// clz
						6'b000000: begin
							in1 = rs1_rev8_b;
							in2 = 64'(-1);
							add_cin = '0;
							in3 = add_add;
							in4 = in1;
							logical_invert_arg2 = '1;
							in5 = logical_and;
							rd = popcnt_cpop;
						end

						// ctz
						6'b000001: begin
							in1 = rs1;
							in2 = 64'(-1);
							add_cin = '0;
							in3 = add_add;
							in4 = in1;
							logical_invert_arg2 = '1;
							in5 = logical_and;
							rd = popcnt_cpop;
						end

						// cpop
						6'b000010: begin
							in5 = rs1;
							rd = popcnt_cpop;
						end

						// sext.b
						6'b000100: begin
							rd = rs1sb;
						end

						// sext.h
						6'b000101: begin
							rd = rs1sh;
						end

						default: sigill = '1;
					endcase

					// binvi
					6'b011010: begin
						in3 = rs1;
						in4 = imm_decoded;
						logical_invert_arg2 = '0;
						rd = logical_xor;
					end

					default: sigill = '1;
				endcase

				// slti, sltiu
				3'b01?: begin
					in3 = rs1;
					in4 = imm;
					cmp_signed = ~funct3[0];
					rd = 64'(cmp_lt);
				end

				// xori
				3'b100: begin
					in3 = rs1;
					in4 = imm;
					logical_invert_arg2 = '0;
					rd = logical_xor;
				end

				3'b101: unique casez (imm[6+:6])
					// srli, srai
					6'b0?0000: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_arithmetic = imm[10];
						shift_rotate_w = opcode[1];
						rd = shift_rotate_result;
					end

					6'b001010: unique case (imm[0+:6])
						// orc.b
						6'b000111: begin
							rd = rs1_orc_b;
						end

						default: sigill = '1;
					endcase

					// bexti
					6'b010010: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_w = opcode[1];
						rd = 64'(shift_rotate_result[0]);
					end

					// rori
					6'b011000: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_w = opcode[1];
						rd = shift_rotate_result;
					end

					6'b011010: unique case (imm[0+:6])
						// rev8
						6'b111000: begin
							rd = rs1_rev8;
						end

						default: sigill = '1;
					endcase

					default: sigill = '1;
				endcase

				// ori
				3'b110: begin
					in3 = rs1;
					in4 = imm;
					logical_invert_arg2 = '0;
					rd = logical_or;
				end

				// andi
				3'b111: begin
					in3 = rs1;
					in4 = imm;
					logical_invert_arg2 = '0;
					rd = logical_and;
				end
			endcase

			// auipc
			OpCode_Auipc: begin
				in1 = {pc, 1'b0};
				in2 = imm;
				add_cin = '0;
				rd = add_add;
			end

			OpCode_OpImm32: unique case (funct3)
				// addiw
				3'b000: begin
					in1 = rs1;
					in2 = imm;
					add_cin = '0;
					rd = add_addw;
				end

				3'b001: unique casez (imm[5+:7])
					// slliw
					7'b0000000: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_arithmetic = imm[10];
						shift_rotate_w = opcode[1];
						rd = shift_rotate_result;
					end

					// slli.uw
					7'b000010?: begin
						in3 = rs1uw;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_arithmetic = imm[10];
						shift_rotate_w = '0;
						rd = shift_rotate_result;
					end

					7'b0110000: unique case (imm[0+:5])
						// clzw
						5'b00000: begin
							in1 = {32'bx, rs1_rev8_b[32+:32]};
							in2 = 64'(-1);
							add_cin = '0;
							in3 = add_add;
							in4 = in1;
							logical_invert_arg2 = '1;
							in5 = logical_and;
							rd = popcnt_cpopw;
						end

						// ctzw
						5'b00001: begin
							in1 = rs1;
							in2 = 64'(-1);
							add_cin = '0;
							in3 = add_add;
							in4 = in1;
							logical_invert_arg2 = '1;
							in5 = logical_and;
							rd = popcnt_cpopw;
						end

						// cpopw
						5'b00010: begin
							in5 = rs1;
							rd = popcnt_cpopw;
						end

						default: sigill = '1;
					endcase

					default: sigill = '1;
				endcase

				3'b101: unique casez (imm[5+:7])
					// srliw, sraiw
					7'b0?00000: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_arithmetic = imm[10];
						shift_rotate_w = opcode[1];
						rd = shift_rotate_result;
					end

					// roriw
					7'b0110000: begin
						in3 = rs1;
						in4 = {58'bx, imm[0+:6]};
						shift_rotate_right = funct3[2];
						shift_rotate_rotate = imm[9];
						shift_rotate_w = opcode[1];
						rd = shift_rotate_result;
					end

					default: sigill = '1;
				endcase

				default: sigill = '1;
			endcase

			// sb, sh, sw,sd
			OpCode_Store:
				if (funct3[2])
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

				// mul, mulh, mulhsu, mulhu
				10'b0??_0000001: begin
					in3 = rs1;
					mul_arg1_is_signed = ~& funct3[0+:2];
					in4 = rs2;
					mul_arg2_is_signed = ~funct3[1];
					rd = | funct3[0+:2] ? mul_mulh : mul_mul;
				end

				// sll
				10'b001_0000000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_arithmetic = funct7[5];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// bset
				10'b001_0010100: begin
					in3 = rs1;
					in4 = rs2_decoded;
					logical_invert_arg2 = '0;
					rd = logical_or;
				end

				// bclr
				10'b001_0100100: begin
					in3 = rs1;
					in4 = rs2_decoded;
					logical_invert_arg2 = '1;
					rd = logical_and;
				end

				// rol
				10'b001_0110000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// binv
				10'b001_0110100: begin
					in3 = rs1;
					in4 = rs2_decoded;
					logical_invert_arg2 = '0;
					rd = logical_xor;
				end

				// slt, sltu
				10'b01?_0000000: begin
					in3 = rs1;
					in4 = rs2;
					cmp_signed = ~funct3[0];
					rd = 64'(cmp_lt);
				end

				// sh1add
				10'b010_0010000: begin
					in1 = rs1_sh1;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				// xor, xnor
				10'b100_0?00000: begin
					in3 = rs1;
					in4 = rs2;
					logical_invert_arg2 = funct7[5];
					rd = logical_xor;
				end

				// min, minu
				10'b10?_0000101: begin
					in3 = rs1;
					in4 = rs2;
					cmp_signed = ~funct3[0];
					rd = cmp_lt ? rs1 : rs2;
				end

				// sh2add
				10'b100_0010000: begin
					in1 = rs1_sh2;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				// srl, sra
				10'b101_0?00000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_arithmetic = funct7[5];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// czero.eqz
				10'b101_0000111: begin
					in3 = '0;
					in4 = rs2;
					rd = cmp_eq ? '0 : rs1;
				end

				// bext
				10'b101_0100100: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_w = opcode[1];
					rd = 64'(shift_rotate_result[0]);
				end

				// ror
				10'b101_0110000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// or, orn
				10'b110_0?00000: begin
					in3 = rs1;
					in4 = rs2;
					logical_invert_arg2 = funct7[5];
					rd = logical_or;
				end

				// max, maxu
				10'b11?_0000101: begin
					in3 = rs1;
					in4 = rs2;
					cmp_signed = ~funct3[0];
					rd = cmp_lt ? rs2 : rs1;
				end

				// sh3add
				10'b110_0010000: begin
					in1 = rs1_sh3;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				// and, andn
				10'b111_0?00000: begin
					in3 = rs1;
					in4 = rs2;
					logical_invert_arg2 = funct7[5];
					rd = logical_and;
				end

				// czero.nez
				10'b111_0000111: begin
					in3 = '0;
					in4 = rs2;
					rd = cmp_eq ? rs1 : '0;
				end

				default: sigill = '1;
			endcase

			// lui
			OpCode_Lui: begin
				rd = imm;
			end

			OpCode_Op32: unique casez ({funct3, funct7})
				// addw, subw
				10'b000_0?00000: begin
					in1 = rs1;
					in2 = funct7[5] ? ~rs2 : rs2;
					add_cin = funct7[5];
					rd = add_addw;
				end

				// mulw
				10'b000_0000001: begin
					in3 = rs1w;
					mul_arg1_is_signed = '1;
					in4 = rs2w;
					mul_arg2_is_signed = '1;
					rd = mul_mulw;
				end

				// add.uw
				10'b000_0000100: begin
					in1 = rs1uw;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				// sllw
				10'b001_0000000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_arithmetic = funct7[5];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// rolw
				10'b001_0110000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// sh1add.uw
				10'b010_0010000: begin
					in1 = rs1uw_sh1;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				10'b100_0000100: unique case (funct5)
					// zext.h
					5'b00000: begin
						rd = rs1uh;
					end

					default: sigill = '1;
				endcase

				// sh2add.uw
				10'b100_0010000: begin
					in1 = rs1uw_sh2;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				// srlw, sraw
				10'b101_0?00000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_arithmetic = funct7[5];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// rorw
				10'b101_0110000: begin
					in3 = rs1;
					in4 = {58'bx, rs2[0+:6]};
					shift_rotate_right = funct3[2];
					shift_rotate_rotate = funct7[4];
					shift_rotate_w = opcode[1];
					rd = shift_rotate_result;
				end

				// sh3add.uw
				10'b110_0010000: begin
					in1 = rs1uw_sh3;
					in2 = rs2;
					add_cin = '0;
					rd = add_add;
				end

				default: sigill = '1;
			endcase

			OpCode_Branch: unique casez (funct3)
				// beq, bne
				3'b00?: begin
					in1 = {pc, 1'b0};
					in2 = imm;
					add_cin = '0;
					in3 = rs1;
					in4 = rs2;
					jump = funct3[0] ^ cmp_eq;
				end

				3'b01?: sigill = '1;

				// blt, bge, bltu, bgeu
				3'b1??: begin
					in1 = {pc, 1'b0};
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
				rd = {pcnext_in, 1'b0};
				jump = '1;
			end

			// jal
			OpCode_Jal: begin
				in1 = {pc, 1'b0};
				in2 = imm;
				add_cin = '0;
				rd = {pcnext_in, 1'b0};
				jump = '1;
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
					logical_invert_arg2 = '0;
					rd = csr_load_value;
					csr_store_value = logical_or;
				end

				// csrrc
				3'b011: begin
					in3 = csr_load_value;
					in4 = rs1;
					logical_invert_arg2 = '1;
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
					logical_invert_arg2 = '0;
					rd = csr_load_value;
					csr_store_value = logical_or;
				end

				// csrrci
				3'b111: begin
					in3 = csr_load_value;
					in4 = csrimm;
					logical_invert_arg2 = '1;
					rd = csr_load_value;
					csr_store_value = logical_and;
				end

				default: sigill = '1;
			endcase

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

	output bit[width - 1:0] add,
	output bit[width - 1:0] addw
);
	assign add = arg1 + arg2 + width'(cin);
	assign addw = unsigned'(width'(signed'(add[0+:width / 2])));
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
	input bit invert_arg2,

	output bit[width - 1:0] out_and,
	output bit[width - 1:0] out_or,
	output bit[width - 1:0] out_xor
);
	assign out_and = arg1 & ({width{invert_arg2}} ^ arg2);
	assign out_or = arg1 | ({width{invert_arg2}} ^ arg2);
	assign out_xor = ~(out_and | ~out_or);
endmodule

module multiplier #(
	parameter width = 8
) (
	input bit[width - 1:0] arg1,
	input bit arg1_is_signed,
	input bit[width - 1:0] arg2,
	input bit arg2_is_signed,
	output bit[width - 1:0] mulw,
	output bit[width - 1:0] mul,
	output bit[width - 1:0] mulh
);
	wire signed[width * 2 - 1:0] arg1_extended = arg1_is_signed ? (width * 2)'(signed'(arg1)) : signed'((width * 2)'(arg1));
	wire signed[width * 2 - 1:0] arg2_extended = arg2_is_signed ? (width * 2)'(signed'(arg2)) : signed'((width * 2)'(arg2));
	wire signed[width * 2 - 1:0] product = arg1_extended * arg2_extended;

	assign mulw = unsigned'(width'(signed'(product[0+:width / 2])));
	assign mul = product[0+:width];
	assign mulh = product[width+:width];
endmodule

module orc_b #(
	parameter width = 8
) (
	input bit[width / 8 - 1:0][7:0] arg,

	output bit[width / 8 - 1:0][7:0] out
);
	always_comb begin
		foreach (out[i])
			out[i] = {8{| arg[i]}};
	end
endmodule

module popcnt #(
	parameter width = 8
) (
	input bit[width - 1:0] arg,

	output bit[width - 1:0] cpop,
	output bit[width - 1:0] cpopw
);
	function automatic bit[$clog2(width + 1) - 1:0] inner(
		bit[width - 1:0] arg,
		bit[$clog2(width) - 1:0] start_i,
		bit[$clog2(width) - 1:0] end_i
	);
		if (start_i == end_i)
			return ($clog2(width + 1))'(arg[start_i]);
		else
			return
				inner(arg, start_i, (start_i + end_i - 1) / 2) +
				inner(arg, (start_i + end_i + 1) / 2, end_i);
	endfunction

	assign cpopw = width'(inner(arg, 0, width / 2 - 1));
	assign cpop = width'(inner(arg, 0, width - 1));
endmodule

// Combination shifter and rotator.
//
// Ref:
// Matthew Rudolf Pillmeier, "Barrel shifter design, optimization, and analysis", 2001
// pg 53-60 "3.4 Mask-based One's Complement"
// https://core.ac.uk/download/pdf/228646503.pdf
module shift_rotate #(
	parameter width = 8
) (
	input bit[width - 1:0] value,
	input bit[$clog2(width) - 1:0] shamt,
	input bit right,
	input bit rotate,
	input bit arithmetic,
	input bit w,

	output bit[width - 1:0] result
);
	function automatic void round(
		input bit[$clog2(width) - 1:0] shamt,
		input bit right,
		input bit rotate,
		input int i,
		input bit[width - 1:0] r,
		input bit[width - 1:0] p,
		output bit[width - 1:0] r_,
		output bit[width - 1:0] p_
	);
		if (shamt[i]) begin
			r_ = {r[0+:1 << i], r[1 << i+:width - (1 << i)]};
			p_ = {{(1 << i){~right | rotate}}, p[1 << i+:width - (1 << i)]};
		end else begin
			r_ = r;
			p_ = p;
		end
	endfunction

	bit[width - 1:0] value_;
	bit[$clog2(width) - 1:0] shamt_;
	bit[width - 1:0] r;
	bit[width - 1:0] p;

	always_comb begin
		value_ = {w ? value[0+:width / 2] : value[width / 2+:width / 2], value[0+:width / 2]};
		shamt_ = {$clog2(width){~right}} ^ shamt;
		r = right ? value_ : {value_[0], value_[1+:width - 1]};
		p = {1'b1, {(width - 1){right | rotate}}};

		result = 'x;

		for (int i = 0; i < $bits(shamt_) - 1; i++)
			round(shamt_, right, rotate, i, r, p, r, p);

		if (w) begin
			result[0+:width / 2] = (r[0+:width / 2] & p[width / 2+:width / 2]) | ~({(width / 2){~(arithmetic & value_[width - 1])}} | p[width / 2+:width / 2]);
			result[width / 2+:width / 2] = {(width / 2){result[width / 2 - 1]}};

		end else begin
			round(shamt_, right, rotate, $bits(shamt_) - 1, r, p, r, p);

			result = (r & p) | ~({width{~(arithmetic & value_[width - 1])}} | p);
		end
	end
endmodule
