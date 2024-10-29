li fp, -8

lbu a2, 0(fp) # disk_nr
lbu a3, 0(fp) # source
lbu a4, 0(fp) # destination
lbu a5, 0(fp) # spare

# a0: positions = 0

# a1: pegs
# = src |
#       (dest << ((1 + disk_nr_is_odd) * 8)) |
#       (spare << ((2 - disk_nr_is_odd) * 8))
bexti a2, a2, 0 # disk_nr_is_odd
slli a2, a2, 3
li s1, 16
sub s1, s1, a2
sllw a5, a5, s1
or a1, a3, a5
addi a2, a2, 8
sllw a4, a4, a2
or a1, a1, a4

li a2, -1 # i: -1 -> -inf

li a3, 5      # toggle magnet

li s2, -3

# loop
ctz a5, a2 # j

slli a5, a5, 3 # j * 8
ror a0, a0, a5 # positions = positions >>> (j * 8)
andi s1, a0, 0xff # position

slli a4, s1, 3  # *IO = (pegs >> (position * 8)) & 0xff
srlw a4, a1, a4 #
sb a4, 0(fp)    #
sb a3, 0(fp)

addi s1, s1, 1       # next_position = (position + 1 + j & 1) % 3
bexti a4, a5, 3      #
add s1, s1, a4       #
sltiu a4, s1, 3      #
czero.nez a4, s2, a4 #
add s1, s1, a4       #

slli a4, s1, 3  # *IO = (pegs >> (next_position * 8)) & 0xff
srlw a4, a1, a4 #
sb a4, 0(fp)    #
sb a3, 0(fp)

andi a0, a0, -256 # positions = (positions & 0xffffffffffffff00) | next_position
or a0, a0, s1     #

rol a0, a0, a5 # positions = positions <<< (j * 8)

addi a2, a2, -1

j -68 # loop
