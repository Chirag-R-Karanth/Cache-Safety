# expect: 1
# Directed test: hazards — load-use interlock, EX/MEM/WB forwarding,
# branch-after-producer, store-data forwarding.
.text
.globl _start
_start:
	lui  a0, 0x1                # data base = 0x1000
	addi t0, x0, 21
	sw   t0, 0(a0)

	# load-use: consumer immediately after load
	lw   t1, 0(a0)
	add  t2, t1, t1             # 42
	addi t3, x0, 42
	bne  t2, t3, fail

	# load feeding store data directly
	lw   t1, 0(a0)
	sw   t1, 4(a0)
	lw   t2, 4(a0)
	bne  t2, t0, fail

	# EX-EX forwarding chain (back-to-back dependent ALU ops)
	addi t4, x0, 1
	addi t4, t4, 1
	addi t4, t4, 1
	add  t4, t4, t4
	add  t4, t4, t4             # 12
	addi t3, x0, 12
	bne  t4, t3, fail

	# branch immediately after producer (forward into compare)
	addi t5, x0, 21
	beq  t5, t0, 1f
	j    fail
1:
	# store-data forwarding: producer right before store
	addi t6, x0, 99
	sw   t6, 8(a0)
	lw   t1, 8(a0)
	addi t3, x0, 99
	bne  t1, t3, fail

	# load feeding a branch (load-use into compare)
	lw   t1, 0(a0)              # 21
	beq  t1, t0, 2f
	j    fail
2:
	# back-to-back load->store (memory aliasing through the pipeline)
	lw   t1, 4(a0)
	sw   t1, 12(a0)
	lw   t2, 12(a0)
	bne  t2, t0, fail

	# WB->EX forwarding: gap of 3 instructions between producer/consumer
	addi t4, x0, 5
	nop
	nop
	nop
	add  t4, t4, t4             # 10
	addi t3, x0, 10
	bne  t4, t3, fail

	# store-stall + gap-2 forward: producer feeds stores whose MEM wait
	# freezes EX — regression for the WB->EX source surviving `hold`
	addi a1, a0, 0x40
	addi t5, x0, 0x5A
	sw   t5, 0(a1)              # gap-1 (EX/MEM forward)
	sw   t5, 4(a1)              # gap-2 (MEM/WB forward through the stall)
	sw   t5, 8(a1)              # gap-3 (regfile path)
	lw   t2, 4(a1)
	bne  t2, t5, fail
	lw   t2, 8(a1)
	bne  t2, t5, fail
	lw   t2, 0(a1)
	bne  t2, t5, fail

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
