# Build report — Phase 1: Software cache simulator

**Date:** 2026-11-10
**Branch:** `feat/cache-simulator` → `develop`
**PR:** https://github.com/Chirag-R-Karanth/Cache-Safety/pull/13 (squash-merged)
**Tag:** `v0.1-cache-sim`
**Depends on:** Phase 0 (PR #12)

## Goals (from spec §5, Phase 1 + deliverable 1)

- [x] Configurable cache model: size, associativity, line size
- [x] Replacement policies: LRU, FIFO, **tree-PLRU**, random (seeded)
- [x] Write policies: write-back / write-through × write-allocate on/off
- [x] Hit/miss + **AMAT** output (`hit_latency + miss_rate × miss_penalty`)
- [x] Design-space sweeps across size/associativity/line-size/policy
- [x] **3 traces** (≥2 required): `locality_demo`, `loop_reuse`, `stream_stride`
- [x] Tests: hit/miss per policy, cold cache, full associativity, single-line,
      AMAT math, write-policy semantics, PLRU-vs-LRU hand-worked divergence

## What was done

1. **Rewrote `sim/src/cache.cpp`** (readable ~330-line implementation;
   same CLI/CSV contract as Phase 0, extended):
   - `--write-policy wb|wt`, `--write-allocate 0|1`
   - `--hit-latency`, `--miss-penalty` → `amat` metric in summary CSV
   - `--policy lru|fifo|plru|random` + `--seed` (xorshift64\*, deterministic)
   - tree-PLRU (heap-ordered bit array; power-of-2 ways enforced)
   - new metrics: `write_throughs`, `fills`, `amat`, `write_policy`, …
2. **Trace generator** `sim/traces/gen_traces.py` → `loop_reuse.trace`
   (98% hit rate), `stream_stride.trace` (0.8% hit rate); committed inputs.
3. **Sweep harness** `scripts/run_sweep.py` rewritten: 42 configurations
   (3 traces × ways{1,2,4} × policy{LRU,FIFO,PLRU} + capacity curve
   {128…2048} × policy) → `comparison.csv` + 3 SVG charts (deterministic —
   SVG `dc:date` stripped so reruns don't dirty git).
4. **`scripts/analyse.py`** default output → `sim/results/demo/`; demo run +
   HTML report regenerated from raw CSVs.
5. **Test suite expanded 5 → 16** (`sim/tests/test_cache.py`), including a
   hand-worked 4-way PLRU-vs-LRU sequence (tree walk documented below).

### Hand-worked PLRU case (used in tests)

4-way, 1 set; A B C D fill (invalid-first), hits A B C, then E:
tree bits before E = `[0,0,1,0]` → victim walk `0→1→3` = leaf0 = **A**;
after E fills leaf0, bits `[1,1,1,0]` → next victim `0→2→6` = leaf3 = D.
LRU evicts D at E instead, so final A: **hit under LRU, miss under PLRU**
(LRU 5 misses vs PLRU 6 on the 9-access sequence).

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Unit tests (16) | `make test-sim` | **16/16 OK** |
| RTL regression (Phase 0 gate) | `make test-rtl` | PASS `counter=90` |
| Full gate | `make test` | pass |
| Sweep end-to-end | `python3 scripts/run_sweep.py` | 42 configs, 3 charts |
| Demo report | `analyse.py` on raw CSVs | `report.html` + 3 SVGs |
| Trace sanity | hit rates | loop 98.4% / mixed 35% / stream 0.8% |

**Notable bugs caught by tests:** shared output prefix caused stale-summary
reads between policy runs (fixed with per-run `name=`); capacity sweep began
at geometrically impossible 64 B / 2-way config (min 128 B).

## Artifacts

- `sim/src/cache.cpp` (v2), `sim/tests/test_cache.py` (16 tests)
- `sim/traces/{gen_traces.py,loop_reuse.trace,stream_stride.trace}`
- `sim/results/sweep/comparison.csv` + 3 charts
- `sim/results/demo/{run_summary.csv,run_accesses.csv,report.html,*.svg}`
- `docs/results.md` Phase 1 section with interpretations

## Issues / risks

- "Real benchmark traces" (compiled-program address traces) deferred: the
  RISC-V toolchain is now installed (`riscv-none-elf-gcc 15.2.0`, xpack) so
  Phase 2+ can emit traces from actual programs; Phase 1 uses deterministic
  synthetic patterns that bracket real locality behavior.
- `analyse.py` still single-run oriented; multi-run aggregation arrives with
  the dashboard (Phase 8).

## Exit criteria for next phase

Phase 2 (baseline pipeline) starts once this PR squash-merges and `main`
stays green.
