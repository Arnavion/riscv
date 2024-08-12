# zero = LEFT = 0
# a1 = FORWARD = 1
li a1, 1
# a2 = RIGHT = 2
li a2, 2
# a4 = USE = 4
li a4, 4

# loop
sb zero, -8(zero)

# check_and_turn_right
sb a4, -8(zero)
lbu a3, -8(zero)
beqz a3, 12 # done_turning_right
sb a2, -8(zero)
j -16 # check_and_turn_right

# done_turning_right
sb a1, -8(zero)
j -28 # loop
