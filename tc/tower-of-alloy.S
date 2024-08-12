li a4, 5         # toggle magnet

lb a0, -1(zero) # disk_nr
lb a1, -1(zero) # source
lb a2, -1(zero) # destination
lb a3, -1(zero) # spare

j 24 # move_start

# move
#
# a0: disk_nr
# a1: source
# a2: destination
# a3: spare

addi sp, sp, 4
sb s0, -4(sp)
sb s1, -3(sp)
sb s2, -2(sp)
sb s3, -1(sp)

# move_start
mv s0, a0
mv s1, a1
mv s2, a2
mv s3, a3

# move_start_post
beqz s0, 24 # move_middle

addi a0, s0, -1
mv a1, s1
mv a2, s3
mv a3, s2
j -56 # move

# move_middle
sb s1, -1(zero)
sb a4, -1(zero)
sb s2, -1(zero)
sb a4, -1(zero)

beqz s0, 24 # move_end

addi s0, s0, -1
xor s1, s1, s3
xor s3, s1, s3
xor s1, s1, s3
j -60 # move_start_post, tail call

# move_end
lb s0, -4(sp)
lb s1, -3(sp)
lb s2, -2(sp)
lb s3, -1(sp)
addi sp, sp, -4
j -60 # move_middle
