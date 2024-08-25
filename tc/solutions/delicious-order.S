li fp, -8
li sp, 0xff  # end of array
mv a0, sp    # one before array start
addi a1, sp, -15

# next_order
mv a2, a0
lbu a3, 0(fp)
# find_insertion_pos
beq a2, sp, 16 # found_insertion_pos
lbu a4, 1(a2)
bgeu a4, a3, 10 # found_insertion_pos
sb a4, 0(a2)
addi a2, a2, 1
j -14 # find_insertion_pos
# found_insertion_pos
sb a3, 0(a2)
addi a0, a0, -1
bne a0, a1, -24 # next_order

# prev_order
lbu a1, 1(a0)
sb a1, 0(fp)
addi a0, a0, 1
j -6 # prev_order
