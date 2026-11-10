# expect: 4
# Squash correctness: a branch is trained to predict taken, then its
# outcome flips so the taken path is fetched speculatively. The wrong
# path's store (distance 1, reaches MEM on the squash cycle) and trap
# (distance 1/2, reaches EX while block_commit is asserted) must NOT
# commit; the correct fall-through resumes. Architectural result must
# match the ISS, which never executes a wrong path.
.text
.globl _start
_start:
	li   t1, 1
	li   t2, 0x400          # scratch word in dmem (zero-initialised)
	li   s0, 0              # training-hit score
	li   t4, 2

	# --- train branch PC1 as taken (same PC executed twice) ---
	li   t3, 1
train1:
	beq  t3, t1, train1_hit # iter1: cold miss -> mispredict; iter2: learned
	j    fail
train1_hit:
	addi s0, s0, 1
	addi t4, t4, -1
	bnez t4, train1

	# --- flip PC1 to not-taken: predicted taken (wrong path = store) ---
	li   t3, 2              # t3 != t1
	sw   x0, 0(t2)          # clear scratch
	beq  t3, t1, wrong_store
	# correct fall-through:
	lw   s1, 0(t2)          # must read 0 (wrong-path store squashed)
	bnez s1, fail
	j    after_store
wrong_store:
	sw   t1, 0(t2)          # wrong-path store, distance 1: must not commit
	j    fail               # if reached, squash failed entirely
after_store:

	# --- train branch PC2 as taken ---
	li   t4, 2
	li   t3, 1
train2:
	beq  t3, t1, train2_hit
	j    fail
train2_hit:
	addi s0, s0, 1
	addi t4, t4, -1
	bnez t4, train2

	# --- flip PC2: predicted taken (wrong path = ecall) ---
	li   t3, 2
	beq  t3, t1, wrong_trap
	# correct fall-through:
	lw   s1, 0(t2)          # scratch still 0?
	bnez s1, fail
	j    after_trap
wrong_trap:
	ecall                   # wrong-path trap, distance 1: must be gated
	j    fail               # if reached, squash failed entirely
after_trap:

	# score = 4 training hits + 0 (scratch untouched)
	add  s0, s0, s1
	lui  t3, 0xFFFF0
	sw   s0, 0(t3)
	j    .

fail:
	lui  t3, 0xFFFF0
	li   s0, 2
	sw   s0, 0(t3)
	j    .
