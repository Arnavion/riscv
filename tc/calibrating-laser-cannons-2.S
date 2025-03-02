# Computed jump version
#
# fp: IO
# sp: top of stack (last element)
# a0: current input
# a1: previous number
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
	auipc a5, 0


# loop
	lbu a0, 0(fp)

	srli a4, a0, 1
	add a4, a4, a5
	lbu a4, 160(a4)  # cjump
	add a4, a4, a5
	jr a4


# end
	sh a1, 0(fp)


# parse_negative_int
	li a2, -1
	# fallthrough parse_int


# parse_int
	addi sp, sp, -2
	sh a1, 0(sp)
	li a1, 0
	# fallthrough parse_int_inner


# parse_int_inner
	addi a0, a0, -48   # a0 = a0 - '0'

	sh2add a1, a1, a1  # a1 = a1 * 10 + a0
	sh1add a1, a1, a0  #

	lbu a0, 0(fp)      # a0 = *IO
	andi a3, a0, 0xdf  # if (a0 != 0x00 && a0 != 0x20)
	bnez a3, -18       #     goto parse_int_inner

	add a1, a1, a2     # a1 = a2 == -1 ? -a1 : a1
	xor a1, a1, a2     #
	li a2, 0
	j -54  # loop


# op_and
	lhu a3, 0(sp)
	addi sp, sp, 2
	and a1, a3, a1
	lhu s1, 0(fp)
	j -66  # loop


# op_add
	lhu a3, 0(sp)
	addi sp, sp, 2
	add a1, a3, a1
	lhu s1, 0(fp)
	j -78  # loop


# hyphen
	lbu a0, 0(fp)      # a0 = *IO
	andi a3, a0, 0xdf  # if (a0 != 0x00 && a0 != 0x20)
	bnez a3, -68       #     goto parse_negative_int

	lhu a3, 0(sp)
	addi sp, sp, 2
	sub a1, a3, a1
	j -98  # loop


# op_lsl
	lhu a3, 0(sp)
	addi sp, sp, 2
	sll a1, a3, a1
	lhu s1, 0(fp)
	lhu s1, 0(fp)
	j -114  # loop


# op_lsr
	lhu a3, 0(sp)
	addi sp, sp, 2
	srl a1, a3, a1
	lhu s1, 0(fp)
	lhu s1, 0(fp)
	j -130  # loop


# op_xor
	lhu a3, 0(sp)
	addi sp, sp, 2
	xor a1, a3, a1
	lhu s1, 0(fp)
	j -142  # loop


# op_or
	lhu a3, 0(sp)
	addi sp, sp, 2
	or a1, a3, a1
	lhu s1, 0(fp)
	j -154  # loop


# include calibrate-laser-cannons-2.data
