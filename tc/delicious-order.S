# a0: one past array end

li a1, 15

# next_order
mv a2, a0
lbu a3, -1(zero)
# find_insertion_pos
beqz a2, 18 # found_insertion_pos
lbu a4, -1(a2)
bgeu a4, a3, 12 # found_insertion_pos
sb a4, 0(a2)
addi a2, a2, -1
j -16 # find_insertion_pos
# found_insertion_pos
sb a3, 0(a2)
addi a0, a0, 1
bne a0, a1, -30 # next_order

# prev_order
addi a0, a0, -1
lbu a1, 0(a0)
sb a1, -1(zero)
j -10 # prev_order
