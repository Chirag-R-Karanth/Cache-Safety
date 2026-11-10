# expect: 1
# Phase 4: a squashed (wrong-path) load still fills the L1 line.
# The branch at `train` is trained TAKEN twice; its target block loads
# 0x100 and then evicts that line again with two other set-0 lines, so
# 0x100 is cold when the branch flips to not-taken. On the flip the
# predictor still redirects fetch to the target, where the cold
# `lw 0x100` sits at distance 1: it reaches MEM on the squash cycle,
# its fill completes after the flush (latched-fill FSM), and the line
# is valid at exit — the timing-visible side effect Spectre measures.
# The TB checks +expectfill=0x100 (present) and +expectnofill=0x200
# (never touched, absent); the correct fall-through performs a real
# load from 0x000 (must read 0) and stores magic 1.
.text
.globl _start
_start:
	li   t1, 1
	li   t3, 1              # condition: equals t1 -> taken
	li   t4, 2              # two taken training evaluations

train:
	beq  t3, t1, TARGET     # trained taken, then flipped to not-taken

	# --- correct fall-through (only the flip reaches this) ---
	li   t6, 1
	lw   t6, 0(x0)          # real load must complete (0x000 is zeroed)
	bnez t6, fail
	li   s0, 1
	j    done

TARGET:
	lw   t0, 0x100(x0)      # training: legitimate; flip: wrong-path
	lw   t2, 0x000(x0)      # evict helper 1 (same set as 0x100)
	lw   t5, 0x300(x0)      # evict helper 2 -> 0x100 leaves the cache
	addi t4, t4, -1
	bnez t4, train          # second training evaluation
	li   t3, 2              # flip: next evaluation is not-taken
	j    train

done:
	lui  t3, 0xFFFF0
	sw   s0, 0(t3)
	j    .

fail:
	lui  t3, 0xFFFF0
	li   s0, 2
	sw   s0, 0(t3)
	j    .
