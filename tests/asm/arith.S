# expect: 1
# Directed test: ALU register/immediate operations, LUI, AUIPC.
.text
.globl _start
_start:
	# addi / add
	addi t0, x0, 100
	addi t1, x0, 23
	add  t2, t0, t1            # 123
	addi t3, x0, 123
	bne  t2, t3, fail

	# sub
	sub  t2, t0, t1            # 77
	addi t3, x0, 77
	bne  t2, t3, fail

	# and / or / xor
	addi t0, x0, 0x0F0
	addi t1, x0, 0x0FF
	and  t2, t0, t1
	bne  t2, t0, fail
	or   t2, t0, t1
	bne  t2, t1, fail
	xor  t2, t0, t1
	addi t3, x0, 0x00F
	bne  t2, t3, fail

	# shifts
	addi t0, x0, 1
	slli t2, t0, 10            # 1024
	addi t3, x0, 1024
	bne  t2, t3, fail

	addi t0, x0, -1024
	srai t2, t0, 5             # -32
	addi t3, x0, -32
	bne  t2, t3, fail

	srli t2, t0, 20            # 0xFFFFFC00 >> 20 = 4095
	lui  t3, 1
	addi t3, t3, -1
	bne  t2, t3, fail

	# slt / sltu / slti / sltiu
	addi t0, x0, -5
	addi t1, x0, 3
	slt  t2, t0, t1            # 1
	addi t3, x0, 1
	bne  t2, t3, fail
	sltu t2, t0, t1            # 0 (unsigned -5 is huge)
	bne  t2, x0, fail
	slti t2, t0, 0             # 1
	bne  t2, t3, fail
	sltiu t2, x0, -5           # 0 <u 0xFFFFFFFB => 1
	bne  t2, t3, fail

	# lui / auipc
	lui  t0, 0xABCDE
	lui  t1, 0xABCDE
	bne  t0, t1, fail
	auipc t0, 0
	auipc t1, 0
	sub  t2, t1, t0            # 4
	addi t3, x0, 4
	bne  t2, t3, fail

	# shift edge: shamt 31, arithmetic sign propagation
	addi t0, x0, 1
	slli t2, t0, 31            # 0x80000000
	lui  t3, 0x80000
	bne  t2, t3, fail
	srai t2, t2, 31            # -1
	addi t3, x0, -1
	bne  t2, t3, fail

	# andi / ori / xori
	addi t0, x0, 0x555
	andi t2, t0, 0x333         # 0x111
	addi t3, x0, 0x111
	bne  t2, t3, fail
	ori  t2, x0, -1
	addi t3, x0, -1
	bne  t2, t3, fail
	xori t2, t3, 0x0FF         # -1 ^ 0xFF = 0xFFFFFF00
	addi t3, x0, -256          # 0xFFFFFF00
	bne  t2, t3, fail

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
