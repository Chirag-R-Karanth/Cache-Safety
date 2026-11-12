# expect: 1
# Phase 5: Spectre v1 proof-of-concept (simulation).
#
# Attack structure (see docs/build-reports for the timing argument):
#   * victim holds a secret byte in its own array (0x0400) and derives
#     probe_ptr = probe[secret * 16] before the bounds check — in a wide
#     out-of-order core both the OOB secret read and the probe load fit
#     in the speculative window; in this in-order core the late-resolve
#     squash (branch WB) leaves a window of exactly ONE wrong-path
#     instruction, so the address is pre-computed and the wrong path is
#     the single probe load.
#   * the bounds check (bge) is mistrained as "in bounds" (2 evals keep
#     the 2-bit BHT at weakly-not-taken, BTB never sees a taken during
#     training); the flip eval uses an OOB index so the architectural
#     path jumps to `measured` while the predicted fall-through — the
#     wrong path — executes `lw probe[secret]` at distance 1.
#   * Flush+Reload: before each flip the candidate line probe[b] is
#     dropped with an exact invalidate (store to 0xFFFF0001 makes the
#     TB pulse inval_valid/inval_addr). After the flip the reload of
#     probe[b] is timed with the mcycle CSR: a hit (fast) means the
#     squashed load refilled it, i.e. b == secret.
#   * one256-point sweep per trial; N trials with a different secret
#     each (xorshift32). Results: word0 = secret, words 1..256 =
#     latency[b] per trial at 0x2000 (257-word blocks).
#
# The TB dumps the result region on the magic store (+DUMPADDR/
# +DUMPWORDS -> RES lines); scripts/plot_spectre.py builds the
# signature plot and verifies the dip.
.text
.globl _start
_start:
	li   s0, 0x1000            # probe base (256 x 16 B)
	li   s4, 0x2000            # results base
	li   s5, 7                 # N trials
	li   s3, 0                 # trial counter
	li   a1, 8                 # bounds (len)
	li   s7, 0xDEADBEEF        # xorshift seed

trial_loop:
	# ---- new secret byte for this trial (xorshift32, no MUL needed) ----
	slli t0, s7, 13
	xor  s7, s7, t0
	srli t0, s7, 17
	xor  s7, s7, t0
	slli t0, s7, 5
	xor  s7, s7, t0
	andi s6, s7, 0xFF          # secret byte
	li   t1, 0x0400
	sw   s6, 0(t1)             # store into the secret array
	lbu  s6, 0(t1)             # victim reads its own secret (byte, zero-ext)
	slli s1, s6, 4
	add  s1, s1, s0            # probe_ptr = probe + secret*16

	# results[trial][0] = secret
	slli t1, s3, 8
	add  t1, t1, s3            # trial*257 words = trial*256 + trial
	slli t1, t1, 2
	add  t1, t1, s4
	sw   s6, 0(t1)

	li   s2, 0                 # candidate b = 0
cand_loop:
	# ---- mistrain the bounds-check PC as not-taken (2 evals) ----
	li   a0, 0                 # in-bounds
	li   t4, 2
mtrain:                         # <-- bounds-check branch PC (fixed)
	bge  a0, a1, measured      # train: not taken; flip: taken (OOB)
	lw   t3, 0(s1)             # training: architectural probe[secret]
	addi t4, t4, -1
	bnez t4, mtrain

	# ---- flush candidate probe[b] (exact invalidate via TB) ----
	slli t0, s2, 4
	add  t0, t0, s0            # &probe[b]
	lui  t1, 0xFFFF0
	addi t1, t1, 1             # 0xFFFF0001: flush-request magic
	sw   t0, 0(t1)             # TB: inval_addr = data, 1-cycle pulse

	# ---- flip: OOB index, still predicted not-taken ----
	li   a0, 99                # >= len -> architectural path = measured
	j    mtrain                # wrong path (pred NT) = probe load

measured:                       # <-- bge target: only the flip lands here
	slli t0, s2, 4
	add  t0, t0, s0            # &probe[b]
	csrr t5, mcycle
	lw   t3, 0(t0)             # Flush+Reload probe: hit iff squashed fill
	csrr t6, mcycle
	sub  t6, t6, t5            # latency in cycles

	# results[trial][1 + b] = latency
	slli t1, s3, 8
	add  t1, t1, s3            # trial*257
	addi t1, t1, 1             # + secret slot
	add  t1, t1, s2            # + b
	slli t1, t1, 2
	add  t1, t1, s4
	sw   t6, 0(t1)

	addi s2, s2, 1
	li   t0, 256
	bne  s2, t0, cand_loop

	addi s3, s3, 1
	bne  s3, s5, trial_loop

	# ---- done: magic = 1 ----
	lui  t3, 0xFFFF0
	li   t0, 1
	sw   t0, 0(t3)
	j    .
