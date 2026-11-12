# Build report — Phase 6: Meltdown proof-of-concept

**Date:** 2026-11-12
**Branch:** `main`
**PR:** https://github.com/Chirag-R-Karanth/Cache-Safety/pull/18 (squash-merged)
**Tag:** `v0.6-meltdown-poc`
**Depends on:** Phase 5 (PR #17, tag `v0.5-spectre-poc`)
**Issue:** #7 (closed)

## Goals (from spec §5, Phase 6)

- [x] Add minimal privilege mode + protected memory region
- [x] Demonstrate Meltdown: a load executes before the fault/permission check
      completes, leaving a cache side channel
- [x] Measure leak success rate (probe[secret] line present in L1 after fault)
- [x] No regressions to Phases 2–5

## Design

1. **`rtl/core/csr.sv`** — Added `mstatus` CSR (0x300) with bit 0 = `UPRIV`
   (1 = user mode, 0 = machine/supervisor). Read/write via CSR instructions
   (`csrrw`/`csrrs`/`csrrc`). New output `priv_user = mstatus_q[0]` drives the
   mem_stage permission check. Counters (cycle/instret/mcycle/minstret)
   remain read-only as before.

2. **`rtl/core/mem_stage.sv`** — Added inputs `priv_user`, outputs
   `fault_valid`/`fault_addr`. Protected region defined as `PROT_BASE =
   32'h3000` (addresses >= 0x3000 are kernel-only). A load/store targeting a
   protected address while `priv_user` is asserted sets `fault_valid`. The
   fault is reported to the scoreboard but does not immediately trap — it is
   deferred to give dependent transient instructions a window to execute.

3. **`rtl/core/scoreboard.sv`** — Extended with a 5-stage fault scoreboard
   (flt_p0–flt_p4) alongside the existing 2-stage branch scoreboard. A fault
   detected in MEM propagates through the pipeline: p4→p3→p2→p1→p0→squash,
   giving ~4 cycles of speculative execution after the fault is detected.
   `squash = br_p0 || flt_p0`, `trap = flt_p0` (only faults trap),
   `block_commit` asserted for the full window (suppresses wrong-path CSR
   writes/traps/training, but speculative loads still pass through — their
   cache side effects survive the flush per Phase 4).

4. **`rtl/core/core5.sv`** — Wired `csr.priv_user → mem_stage.priv_user`,
   `mem_stage.fault_valid/fault_addr → scoreboard`, and
   `scoreboard.trap || execute.trap_valid → core5.trap`. Existing branch
   timing unchanged (2-stage scoreboard preserved).

5. **`tb/integration/tb_core.sv`** — Added trap delay: on `trap`, wait 10
   cycles before calling `finish_stats` so in-flight speculative cache fills
   (e.g. the Meltdown probe load) can complete before `+expectfill` /
   `+expectnofill` inspects the cache state.

6. **`tests/asm/meltdown.S`** — The Meltdown victim:
   - Kernel mode stores secret byte (0x42) at protected address 0x3FF0
   - Kernel mode touches 0x3FF0 (dummy load) so the line is in the cache —
     this makes the faulting load a cache hit, avoiding the load-use stall
     that would otherwise consume the speculative window
   - Flushes probe[0x42] line (0x1420) via TB invalidate magic (0xFFFF0001)
   - Switches to user mode (`csrrw x0, mstatus, 1`)
   - `lbu` from 0x3FF0 faults (user + protected) but is a cache hit: the
     loaded byte is transiently available to `slli`/`add`/`lw`, which index
     probe[secret] and fill that line before the trap retires
   - TB verifies `+expectfill=0x1420` → probe[secret] cached → PASS

7. **`tests/run_riscv_tests.sh`** — `meltdown` test gets `+expectfill=1420`.
   Skips the MAGIC check (test ends with TRAP, not a magic store); validates
   TRAP occurred and EXPECTFILL PASS.

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Meltdown fault detected | `make test-riscv` | **PASS** (`trap triggered`) |
| Cache side channel (probe[secret] cached) | `make test-riscv` | **PASS** (`EXPECTFILL PASS`) |
| Full suite (directed + ISS + 20 random) | `make test-riscv` | **31 passed, 0 failed** |
| Phase 5 regression (spectre_v1) | `make test-riscv` | **7/7 secrets recovered** |
| Phase 4 regression (squash_fill) | `make test-riscv` | **EXPECTFILL/EXPECTNOFILL PASS** |

## Artifacts

- `rtl/core/csr.sv` (mstatus CSR + priv_user output)
- `rtl/core/mem_stage.sv` (permission fault detection)
- `rtl/core/scoreboard.sv` (5-stage fault scoreboard)
- `rtl/core/core5.sv` (wiring + trap output)
- `tb/integration/tb_core.sv` (trap delay for fill completion)
- `tests/asm/meltdown.S` (Meltdown victim)
- `tests/run_riscv_tests.sh` (meltdown test + expectfill check)

## Issues / risks

- The fault scoreboard window (5 stages) is tuned for the specific
  instruction sequence in meltdown.S. A longer dependency chain between the
  faulting load and the probe load would require more stages.
- The protected region base (0x3000) is fixed in RTL. Test programs must
  keep code/data below 0x3000 (the linker script places data at 0x2000, so
  this is compatible).
- The TB's trap delay (10 cycles) assumes the probe load's cache fill
  completes within that window. A slower memory model would need more delay.
- The `lw` instruction with nonzero immediate + register base
  (e.g. `lw s0, 0x1000(t6)`) is rejected by this toolchain's assembler;
  use `lui` + `add` + `lw s0, 0(t6)` instead.

## Exit criteria

Phase 6 is complete once this PR squash-merges to `main` and is tagged
`v0.6-meltdown-poc`. This demonstrates both cache side channels (Spectre v1
and Meltdown) on core5, addressing issue #7. Phase 7 (mitigations) is next.
