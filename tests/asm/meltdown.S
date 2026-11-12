# expect: 1
# Phase 6: Meltdown proof-of-concept (simulation).
#
# Threat model: a user-mode program must not be able to architecturally read
# the kernel-only region (addr >= PROT_BASE = 0x3000). A hardware permission
# check faults on any user-mode load/store to that region. However — like real
# out-of-order cores — the fault is detected late enough (mem stage) that
# dependent transient instructions execute before the trap retires. Their
# cache side effects survive the flush (Phase 4's speculative-fill property),
# producing a Flush+Reload signature.
#
# Test flow:
#   1. Kernel mode: store secret byte (0x42) at protected address 0x3FF0.
#   2. Kernel mode: touch 0x3FF0 (dummy load) so the line is in the cache —
#      this makes the faulting load a cache hit, avoiding the load-use stall
#      that would otherwise eat the speculative window.
#   3. Flush probe[0x42] line (0x1420 = 0x1000 + 0x42*16) via TB invalidate
#      magic (store to 0xFFFF0001, in kernel mode so it doesn't fault).
#   4. Switch to user mode (mstatus.UPRIV = 1 via csrrw to CSR 0x300).
#   5. Meltdown: lbu from 0x3FF0 faults (user + protected), but is a cache
#      hit so the loaded byte is transiently available to slli + add + lw,
#      which index probe[secret] and fill that line in the L1 before the trap
#      retires.
#   6. Trap fires; TB delay lets the fill complete; +expectfill=0x1420
#      confirms probe[secret] is cached -> the secret leaked via the cache
#      side channel.
#
# Address map:
#   0x3FF0   secret byte (protected, kernel-only)  -> value 0x42
#   0x1000   probe base (256 lines x 16 bytes, not protected)
#   0x1420   probe[0x42] line (expected secret)
#   0xFFFF0000 magic signature (store to finish)
#   0xFFFF0001 flush magic (store addr as data -> TB pulses inval_*)

.text
.globl _start
_start:
	# ---- Kernel mode: store secret at protected address ----
	li   t0, 0x3FF0          # secret address (>= PROT_BASE, kernel-only)
	li   t1, 0x42            # secret byte
	sb   t1, 0(t0)           # store secret (kernel mode: allowed; NWA, no cache fill)

	# ---- Touch the secret address to bring its line into the cache ----
	lbu  t2, 0(t0)           # cache miss -> fill 0x3FF0 line (kernel mode: allowed)

	# ---- Flush probe[0x42] line via TB invalidate magic ----
	li   t2, 0x1000          # probe base
	li   t3, 0x1420          # probe[0x42] = 0x1000 + 0x42*16
	li   t4, 0xFFFF0
	addi t4, t4, 1           # 0xFFFF0001: flush-request magic
	sw   t3, 0(t4)           # TB: inval_addr = probe[0x42], 1-cycle pulse

	# ---- Switch to user mode (mstatus.UPRIV = 1) ----
	li   t4, 1               # user-mode bit
	csrrw x0, 0x300, t4      # write mstatus (CSR 0x300) -> enter user mode

	# ---- Meltdown: transient load from protected address ----
	# Cache hit (line was touched above), so no load-use stall:
	# slli + add + lw execute before the fault squash retires.
	lbu  t5, 0(t0)           # faulting load (user mode + protected): t5 = secret (transient)
	slli t6, t5, 4           # t6 = secret * 16     (depends on faulting load)
	add  t6, t6, t2          # t6 = &probe[secret]  (probe base + secret*16)
	lw   s0, 0(t6)           # probe load -> fills probe[secret] line in L1

	# Trap fires here (fault scoreboard squashes pipeline).
	# probe[0x42] line is cached -> +expectfill=0x1420 -> PASS.
	j    .

fail:
	# Not reached: trap terminates the test before this.
	lui  t3, 0xFFFF0
	li   t0, 2
	sw   t0, 0(t3)
	j    .
