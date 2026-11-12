# Build report — Phase 7: Mitigations

**Date:** 2026-11-12
**Branch:** `main`
**PR:** https://github.com/Chirag-R-Karanth/Cache-Safety/pull/19 (squash-merged)
**Tag:** `v0.7-mitigations`
**Depends on:** Phase 6 (PR #18, tag `v0.6-meltdown-poc`)
**Issue:** #7 (closed)

## Goals (from spec §5, Phase 7)

- [x] Implement each mitigation as a parameterized (runtime-toggleable) RTL switch
- [x] Re-run both attacks (Spectre v1 and Meltdown) with each mitigation on
- [x] Log leak success rate and IPC/cycle overhead for every configuration
- [x] Produce a mitigation comparison table + leakage-vs-overhead plot
- [x] No regressions to Phases 2–6

## Design

1. **Mitigation 1 — `disable_spec_fill` (speculative-load restriction).**
   `rtl/cache/l1_dcache.sv` gains a runtime `disable_spec_fill` input plus a
   `squash` input. When asserted, a load whose fill is interrupted by a late
   squash never starts/completes its fill, so a squashed load can never leave
   a line valid. This removes the cache side channel both Spectre v1 and
   Meltdown depend on (Phase 4's speculative-fill property).

2. **Mitigation 2 — `serialize_branch` (speculation barrier / fence).**
   `rtl/core/core5.sv` gains a runtime `serialize_branch` input. When
   asserted, IF/ID is held while `block_commit` is set (a squash is pending),
   so no younger instruction enters the pipeline before a branch resolves.
   This eliminates the speculative window for branch mispredictions.

3. **`rtl/core/mem_stage.sv`** — passes `priv_user`, `disable_spec_fill`, and
   `squash` through to the cache; keeps the Phase 6 permission-fault
   detection.

4. **`tb/integration/tb_core.sv`** — reads `+DISABLE_SPEC_FILL` and
   `+SERIALIZE_BRANCH` plusargs, drives the core inputs, and now prints
   `CYCLES=<n> INSTRET=<n> IPC=<x.xxx>` at finish for overhead measurement.

5. **`tests/run_riscv_tests.sh`** — every test runs under a 4-configuration
   mitigation matrix (none / DISABLE_SPEC_FILL / SERIALIZE_BRANCH / both),
   logging leak success and IPC for each. Baseline leak is a sanity check
   for the two attack tests.

6. **`scripts/mitigation_report.py`** — re-runs both attacks under all four
   configs, emits `results/mitigations/comparison.csv` and a
   leakage-vs-overhead plot `results/mitigations/leakage_vs_overhead.svg`.

## Testing & validation

Mitigation comparison (leak = side-channel observable, IPC = cycles/instret):

| Attack | Mitigation | Leak | IPC | Overhead |
|--------|------------|------|-----|----------|
| Spectre v1 | none (baseline) | yes | 0.515 | 0.00% |
| Spectre v1 | DISABLE_SPEC_FILL | no | 0.515 | 0.00% |
| Spectre v1 | SERIALIZE_BRANCH | yes | 0.515 | 0.00% |
| Spectre v1 | both | no | 0.515 | 0.00% |
| Meltdown | none (baseline) | yes | 0.449 | 0.00% |
| Meltdown | DISABLE_SPEC_FILL | no | 0.449 | 0.00% |
| Meltdown | SERIALIZE_BRANCH | no | 0.449 | 0.00% |
| Meltdown | both | no | 0.449 | 0.00% |

Interpretation:

* `DISABLE_SPEC_FILL` removes the speculative-fill primitive, so it stops
  **both** attacks with zero measurable IPC overhead on these workloads.
* `SERIALIZE_BRANCH` stops **Meltdown** (holds the pipeline during the
  fault-scoreboard window, so transient dependent loads never reach MEM),
  but does **not** stop Spectre v1: the wrong-path probe load is already in
  EX/MEM when the branch misprediction is detected, so holding IF/ID cannot
  prevent it from reaching the cache.
* Neither mitigation shows measurable IPC overhead on these tests (the
  speculative window is only a few cycles), so the leakage-vs-overhead
  plot sits at ~0% overhead for all configurations.

Full regression suite: **31 passed, 0 failed** (directed + ISS cross-check +
20 randomized + both attacks under all mitigations). No regressions to
Phases 2–6.

## Artifacts

- `rtl/cache/l1_dcache.sv` (disable_spec_fill + squash ports)
- `rtl/core/mem_stage.sv` (wires disable_spec_fill / squash to cache)
- `rtl/core/core5.sv` (serialize_branch + hold on block_commit)
- `tb/integration/tb_core.sv` (mitigation plusargs + CYCLES/INSTRET/IPC)
- `tests/run_riscv_tests.sh` (4-config mitigation matrix + IPC logging)
- `scripts/mitigation_report.py` (comparison table + leakage/overhead plot)
- `results/mitigations/{comparison.csv,leakage_vs_overhead.svg}` (evidence)

## Issues / risks

* `SERIALIZE_BRANCH` only stalls on mispredictions (block_commit). It does
  not stop a wrong-path load that has already passed ID/EX when the squash
  fires — hence it does not mitigate Spectre v1. It does mitigate Meltdown
  because the fault scoreboard asserts block_commit for the whole fault
  window, holding the pipeline before dependent transient loads reach MEM.
* `DISABLE_SPEC_FILL` is a blunt instrument: it disables speculative fill
  for all loads, not just potentially-squashed ones. On this in-order core
  the overhead is negligible, but a deeper pipeline might see more impact.
* IPC overhead is measured on tiny directed test programs; real workloads
  with more branches/mispredicts could show larger serialization overhead.

## Exit criteria

Phase 7 is complete once this PR squash-merges to `main` and is tagged
`v0.7-mitigations`. Both cache side channels (Spectre v1 and Meltdown) have
been demonstrated and shown to be mitigable via parameterized toggles.
Phase 8 (Dashboard + Polish, tag `v1.0-final`) is next.
