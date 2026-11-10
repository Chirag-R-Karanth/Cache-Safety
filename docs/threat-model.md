# Threat model: what this project demonstrates, and what it does not

## Purpose

This project is a **semester-grade educational demonstration** of two classes of
transient-execution attacks — **Spectre v1** (branch-predictor mistraining →
speculative out-of-bounds read → Flush+Reload cache side channel) and a
**Meltdown-style** privilege-ordering flaw (protected load use before privilege
check completes) — executed on a **custom, deliberately instrumented RV32I
core** implemented in SystemVerilog, plus the mitigations that stop them.

## In scope (what we demonstrate)

| # | Claim | Evidence produced |
|---|---|---|
| 1 | A speculative in-order core with a late-resolving branch can execute younger loads down a mispredicted path | Pipeline testbench waveforms (VCD) showing fetch/execute past an unresolved branch |
| 2 | Speculative execution leaves **persistent microarchitectural state** (cache line residency) even after the wrong-path instructions are squashed | RTL test: squashed load still changes L1 tag array (Phase 4 test) |
| 3 | An attacker can mistrain a 2-bit saturating-counter predictor + BTB, trigger an out-of-bounds speculative read of a *secret byte*, and recover it via Flush+Reload probe latencies | 256-entry probe-latency plot with a single dip at the secret byte; recovery rate across N trials |
| 4 | A delayed privilege-check-vs-use ordering on a load lets user-mode code transiently read a supervisor-only address into cache state before the fault is taken | Meltdown-style testbench: protected word's cache line becomes resident pre-fault; leak rate vs trials |
| 5 | Hardware mitigations (speculation barrier, check-before-forward, cache-fill-on-commit) reduce leak success toward zero at a measurable cycle/IPC cost | Comparison table: leak rate × overhead per mitigation toggle |

## Out of scope (what we explicitly do NOT claim)

1. **No claims about real CPUs.** Nothing here establishes or refutes security
   guarantees for Intel/AMD/ARM silicon. Our core is a *model* chosen so the
   attack mechanics are visible and controllable cycle-by-cycle.
2. **No real secrets.** The "secret" is a known byte placed in a simulated
   memory array by our own testbench. We never read host process memory,
   kernel memory, or any data the operator did not put there.
3. **No cross-process/cross-VM attack.** Everything runs inside one simulated
   address space (or one PYNQ overlay process) under our control.
4. **No denial-of-service, persistence, or weaponization.** Outputs are
   charts, CSVs and waveforms.
5. **No full out-of-order execution.** The core is in-order issue with a
   scoreboard-gated speculative window — the minimum needed for Spectre v1.
   We do not model reorder buffers, SMT, or prefetcher side channels beyond
   the L1 D-cache.

## Why a toy core is necessary and sufficient

- **Necessary:** real CPUs hide the exact pipeline timing we need to observe
  (fetch width, speculation window length, privilege-check latency are
  opaque and microcode-dependent). A custom core lets us *pause* the world at
  the speculation window, dump the tag array, and toggle mitigations as RTL
  parameters — impossible on production silicon without root and PMU access.
- **Sufficient:** Spectre v1 and Meltdown-style leaks require only four
  ingredients, all of which our core models explicitly:
  1. a predictor that can be mistrained (2-bit BHT + BTB),
  2. transient execution past a check/branch (scoreboard + late resolve),
  3. a covert channel with eviction+probe (set-associative L1 + Flush+Reload
     timing via the cycle-counter CSR),
  4. (Meltdown) a use that precedes a permission decision (delayed privilege
     check on the load path).

## Operator responsibilities

- Run simulations and the PYNQ overlay only on hardware you own or are
  authorized to use.
- Treat recovered bytes as *demonstration data*; do not point the memory
  arrays at real secrets.
- Dashboard outputs may contain probe traces; they contain no host secrets
  by construction.

## Residual risks in the model (labeled assumptions)

- The software cache simulator (`sim/`) is functional, not timing-accurate;
  AMAT numbers are analytical estimates.
- Flush+Reload on FPGA uses the cycle-counter CSR; DDR refresh and PS-PL
  contention add noise not present in RTL simulation — recovery rates are
  reported for both environments separately.
- The privilege model is two-level (U/S) with a single protected page —
  enough for the ordering bug, not a MMU.
