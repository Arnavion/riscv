li a5, -1

li a4, 5         # toggle magnet

lbu a0, 0(a5) # disk_nr
lbu a1, 0(a5) # source
lbu a2, 0(a5) # destination
lbu a3, 0(a5) # spare

li sp, 0x100
j 12 # move_start

# move
#
# a0: disk_nr
# a1: source
# a2: destination
# a3: spare

addi sp, sp, -16
sw s0, 0(sp)
sw s1, 4(sp)
sw s2, 8(sp)
sw s3, 12(sp)

# move_start
mv s0, a0
mv s1, a1
mv s2, a2
mv s3, a3

# move_start_post
beqz s0, 14 # move_middle

addi a0, s0, -1
mv a1, s1
mv a2, s3
mv a3, s2
j -30 # move

# move_middle
sb s1, 0(a5)
sb a4, 0(a5)
sb s2, 0(a5)
sb a4, 0(a5)

beqz s0, 18 # move_end

addi s0, s0, -1
xor s1, s1, s3
xor s3, s1, s3
xor s1, s1, s3
j -40 # move_start_post, tail call

# move_end
lw s0, 0(sp)
lw s1, 4(sp)
lw s2, 8(sp)
lw s3, 12(sp)
addi sp, sp, 16
j -38 # move_middle
