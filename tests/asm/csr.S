# expect: 1
# Directed test: cycle/instret CSRs — monotonic counters, read-only writes.
.text
.globl _start
_start:
	csrr t0, cycle
	nop
	nop
	nop
	csrr t1, cycle
	beq  t1, t0, fail           # cycle must advance
	bltu t1, t0, fail           # cycle never goes backwards

	csrr t2, instret
	nop
	nop
	csrr t3, instret
	beq  t3, t2, fail           # instret must advance
	bltu t3, t2, fail

	# machine aliases read the same counters
	csrr t4, mcycle
	beq  t4, x0, fail           # some cycles have passed since reset
	csrr t5, minstret
	beq  t5, x0, fail

	# csrrw to a read-only counter: returns old value, counter keeps counting
	csrrw t6, cycle, t0
	beq  t6, x0, fail
	csrr  a1, cycle
	bltu  a1, t6, fail

	# csrrsi with zimm=0 is a pure read
	csrrsi a2, instret, 0
	beq   a2, x0, fail

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
