# expect: 1
# Directed test: loads/stores — widths, sign extension, byte lanes.
.text
.globl _start
_start:
	lui  a0, 0x1               # data base = 0x1000

	# word round-trip
	addi t0, x0, 0x123
	sw   t0, 0(a0)
	lw   t1, 0(a0)
	bne  t1, t0, fail

	# half stores/loads, sign vs zero extension
	addi t0, x0, -2             # low half = 0xFFFE
	sh   t0, 4(a0)
	lhu  t1, 4(a0)
	addi t3, x0, -2
	slli t3, t3, 16
	srli t3, t3, 16             # 0x0000FFFE
	bne  t1, t3, fail
	lh   t1, 4(a0)
	bne  t1, t0, fail           # sign-extended = -2

	# bytes at lanes 0/1
	addi t0, x0, 0x7F
	sb   t0, 8(a0)
	addi t0, x0, -1
	sb   t0, 9(a0)
	lb   t1, 9(a0)
	bne  t1, t0, fail           # sign-extended 0xFF -> -1
	lbu  t1, 9(a0)
	addi t3, x0, 255
	bne  t1, t3, fail
	lb   t1, 8(a0)
	addi t3, x0, 127
	bne  t1, t3, fail

	# byte lanes 2/3 of a word
	lui  t0, 0x12345
	addi t0, t0, 0x678          # 0x12345678
	sw   t0, 12(a0)
	lbu  t1, 14(a0)             # byte 2 = 0x34
	addi t3, x0, 0x34
	bne  t1, t3, fail
	lbu  t1, 15(a0)             # byte 3 = 0x12
	addi t3, x0, 0x12
	bne  t1, t3, fail

	# overwrite byte 3, re-read whole word: 0x7F345678
	addi t0, x0, 0x7F
	sb   t0, 15(a0)
	lw   t1, 12(a0)
	lui  t3, 0x7F345
	addi t3, t3, 0x678
	bne  t1, t3, fail

	# negative offset addressing from a mid-pointer
	addi a1, a0, 16
	sw   t0, -16(a1)            # back to 0(a0)
	lw   t1, 0(a0)
	bne  t1, t0, fail

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
