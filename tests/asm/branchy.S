# expect: 0x29c0
# Branchy benchmark: data-dependent branch chains + tight counted loops.
# The TB prints a STAT line (branches/mispredicts) for this test; the
# architectural result is cross-checked against the ISS (no CSRs used).
.text
.globl _start
_start:
	li   s0, 0              # checksum
	li   s1, 0              # i
	li   s2, 0              # odd/even accumulator
	li   s3, 40             # outer iterations

outer:
	# data-dependent 4-way chain on i&3 (mixed taken/not-taken)
	andi t0, s1, 3
	beq  t0, x0, c0
	li   t1, 1
	beq  t0, t1, c1
	li   t1, 2
	beq  t0, t1, c2
	xori s0, s0, 0x5A       # t0 == 3
	addi s0, s0, 7
	j    cont
c0:
	ori  s0, s0, 0x01
	addi s0, s0, 3
	j    cont
c1:
	andi s0, s0, 0x7F
	addi s0, s0, 11
	j    cont
c2:
	xori s0, s0, 0x33
	addi s0, s0, 5
cont:
	# tight backward loop (BHT should learn taken)
	li   t2, 8
inner:
	add  s0, s0, t2
	addi t2, t2, -1
	bne  t2, x0, inner

	# data-dependent direction mix
	andi t0, s1, 1
	bne  t0, x0, odd
	addi s2, s2, 4
	j    step
odd:
	addi s2, s2, 9
step:
	addi s1, s1, 1
	blt  s1, s3, outer

	xor  s0, s0, s2
	slli t0, s1, 8
	xor  s0, s0, t0
	lui  t3, 0xFFFF0
	sw   s0, 0(t3)
	j    .

fail:
	lui  t3, 0xFFFF0
	li   s0, 0xDEAD
	sw   s0, 0(t3)
	j    .
