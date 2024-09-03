li fp, -8
li a1, 32  # CASE_DIFF, SPACE
li a2, 1   # capitalize

# loop
lbu a0, 0(fp)
czero.eqz a4, a1, a2  # a4 = capitalize ? CASE_DIFF : 0
sub a3, a0, a4        # c2 = c - a4
sb a3, 0(fp)
sub a3, a0, a1        # a3 = c - SPACE
seqz a2, a3           # capitalize = c == SPACE
j -20 # loop
