li fp, -8

li a5, 5         # toggle magnet

lbu a0, 0(fp) # disk_nr
lbu a1, 0(fp) # source
lbu a2, 0(fp) # destination
lbu a3, 0(fp) # spare

li sp, 0x100

# fallthrough move


# move
#
# a0: disk_nr
# a1: source
# a2: destination
# a3: spare

addi sp, sp, -16
sw a0, 0(sp)
sw a1, 4(sp)
sw a2, 8(sp)
sw a3, 12(sp)

addi, a0, a0, -1
mv a4, a2
mv a2, a3
mv a3, a4
bnez a0, -18 # move, tail call
# fallthrough move_inner


# move_inner
sb a1, 0(fp)
sb a5, 0(fp)
sb a2, 0(fp)
sb a5, 0(fp)

lw a0, 0(sp)
lw a3, 4(sp)
lw a2, 8(sp)
lw a1, 12(sp)
addi sp, sp, 16

sb a3, 0(fp)
sb a5, 0(fp)
sb a2, 0(fp)
sb a5, 0(fp)

addi a0, a0, -1
beqz a0, -28 # move_inner, tail call
j -50 # move, tail call
