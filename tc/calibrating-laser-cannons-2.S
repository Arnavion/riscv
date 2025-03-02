# Computed jump version
#
# fp: IO
# sp: top of stack (last element)
# a0: current input
# a1: current token
# a2: current token started with -
#
#
# Tokens
#
# \0 | 0x00
#    | 0x20
# 0  | 0x30
# 1  | 0x31
# 2  | 0x32
# 3  | 0x33
# 4  | 0x34
# 5  | 0x35
# 6  | 0x36
# 7  | 0x37
# 8  | 0x38
# 9  | 0x39
#
#
# Operators
#
# &  | 0x26
# +  | 0x2b
# -  | 0x2d
# << | 0x3c
# >> | 0x3e
# ^  | 0x5e
# |  | 0x7c


	li sp, 0x400000
	li fp, -8


# loop
	lbu a0, 0(fp)

	srli a3, a0, 1
	auipc a4, 0
	sh3add a4, a3, a4
	ld a4, 236(a4)  # cjump
	auipc a3, 0
	add a3, a3, a4
	jr a3


# end
	lhu a1, 0(sp)
	sh a1, 0(fp)


# parse_negative_int
	li a2, -1
	# fallthrough parse_int


# parse_int
	addi a0, a0, -48   # a0 = a0 - '0'
	add a0, a0, a2     # a0 = a2 == -1 ? -a0 : a0
	xor a0, a0, a2     #

	sh2add a1, a1, a1  # a1 = a1 * 10 + a0
	sh1add a1, a1, a0  #

	lbu a0, 0(fp)      # a0 = *IO
	andi a3, a0, 0xdf  # if (a0 != 0x00 && a0 != 0x20)
	bnez a3, -22       #     goto parse_int

	addi sp, sp, -2
	sh a1, 0(sp)

	li a1, 0
	li a2, 0
	j -68  # loop


# op_and
	lhu a4, 0(sp)
	lhu a3, 2(sp)
	and a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	lhu zero, 0(fp)
	j -90  # loop


# op_add
	lhu a4, 0(sp)
	lhu a3, 2(sp)
	add a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	lhu zero, 0(fp)
	j -112  # loop


# hyphen
	lbu a0, 0(fp)      # a0 = *IO
	andi a3, a0, 0xdf  # if (a0 != 0x00 && a0 != 0x20)
	bnez a3, -88       #     goto parse_negative_int

	lhu a4, 0(sp)
	lhu a3, 2(sp)
	sub a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	j -138  # loop


# op_lsl
	lhu a4, 0(sp)
	lhu a3, 2(sp)
	sll a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	lhu zero, 0(fp)
	lhu zero, 0(fp)
	j -166  # loop


# op_lsr
	lhu a4, 0(sp)
	lhu a3, 2(sp)
	srl a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	lhu zero, 0(fp)
	lhu zero, 0(fp)
	j -194  # loop


# op_xor
	lhu a4, 0(sp)
	lhu a3, 2(sp)
	xor a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	lhu zero, 0(fp)
	j -216  # loop


# op_or
	lhu a4, 0(sp)
	lhu a3, 2(sp)
	or a3, a3, a4
	sh a3, 2(sp)
	addi sp, sp, 2
	lhu zero, 0(fp)
	j -238  # loop


# include calibrate-laser-cannons-2.data
