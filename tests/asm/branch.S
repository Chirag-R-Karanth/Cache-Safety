# expect: 1
# Directed test: branches (both directions), JAL, JALR/ret.
.text
.globl _start
_start:
	addi t0, x0, 5
	addi t1, x0, 5
	bne  t0, t1, fail          # not taken
	beq  t0, t1, 1f            # taken
	j    fail
1:
	addi t2, x0, -3
	addi t3, x0, 2
	blt  t2, t3, 2f            # taken: -3 < 2
	j    fail
2:
	bge  t3, t2, 3f            # taken: 2 >= -3
	j    fail
3:
	bltu t2, t3, fail          # not taken: 0xFFFFFFFD <u 2 is false
	bgeu t2, t3, 4f            # taken
	j    fail
4:
	blt  t3, t2, fail          # not taken
	bge  t2, t3, fail          # not taken
	beq  t2, t3, fail          # not taken
	bne  t2, t3, 5f            # taken
	j    fail
5:
	# backward branch loop: sum 4+3+2+1 = 10
	addi t4, x0, 0
	addi t5, x0, 4
6:
	add  t4, t4, t5
	addi t5, t5, -1
	bne  t5, x0, 6b
	addi t3, x0, 10
	bne  t4, t3, fail

	# jal / ret (link register written and honored)
	jal  ra, func
	addi t0, x0, 99
	bne  s0, t0, fail

	# jal with rd=x0 (no link), forward over a trap
	jal  x0, skip
	j    fail
skip:
	# jalr with computed target; ra links to the next instruction
	la   t2, dest
	jalr ra, t2, 0
	j    after_jalr            # ra points here; dest's ret lands on it
	j    fail
dest:
	addi s1, x0, 7
	ret                        # jalr x0, ra, 0
after_jalr:
	addi t3, x0, 7
	bne  s1, t3, fail

pass:
	lui  t0, 0xFFFF0
	addi t1, x0, 1
	sw   t1, 0(t0)
	j    .
fail:
	lui  t0, 0xFFFF0
	addi t1, x0, 2
	sw   t1, 0(t0)
	j    .

func:
	addi s0, x0, 99
	ret
