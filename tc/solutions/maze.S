li fp, -8
# s1 = LEFT = 0
# a1 = FORWARD = 1
li a1, 1
# a2 = RIGHT = 2
li a2, 2
# a4 = USE = 4
li a4, 4

# loop
sb s1, 0(fp)

# check_and_turn_right
sb a4, 0(fp)
lbu a3, 0(fp)
beqz a3, 6 # done_turning_right
sb a2, 0(fp)
j -8 # check_and_turn_right

# done_turning_right
sb a1, 0(fp)
j -14 # loop
