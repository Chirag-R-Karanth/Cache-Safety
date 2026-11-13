# Results

> Every chart is generated from saved raw data under `sim/results/`
> and `results/` (see `docs/ANALYSIS_PLAYBOOK.md` for the reproducibility rules).

## Phase 0 (baseline)

| Check | Result |
|---|---|
| Cache sim builds (`g++ -Wall -Wextra -Wpedantic`) | pass |
| Cache sim unit tests | 5/5 pass |
| PicoRV32 fork standalone Icarus smoke test | pass (`counter=90`) |

## Phase 1 — cache simulator design-space exploration

Raw data: `sim/results/sweep/comparison.csv` (42 configurations × 3 traces);
charts: `hit-rate-comparison.svg`, `hit-rate-vs-capacity.svg`,
`amat-vs-ways.svg`; demo report: `sim/results/demo/report.html`.

Three deterministic traces with deliberately different locality
(`sim/traces/`, regenerable via `gen_traces.py`):

| Trace | Pattern | 4-way LRU hit rate | AMAT (ht=1, pen=50) |
|---|---|---|---|
| `loop_reuse` | hot loop, 4-line working set | **98.4%** | 1.81 cyc |
| `locality_demo` | mixed reuse + conflict | 35% | 33.5 cyc |
| `stream_stride` | column sweep, 8-line stride | **0.8%** | 50.6 cyc |

**Interpretation:** the three curves bracket realistic workload behavior —
temporal locality amortizes almost all miss cost, streaming access pays the
full miss penalty on nearly every access, and the mixed trace sits between.
Associativity helps the conflict-heavy `locality_demo` (1-way 25% → 4-way
35%) but cannot help `stream_stride` (compulsory misses) — exactly the
textbook distinction between conflict/compulsory/capacity misses.

**Capacity curve (2-way LRU, `locality_demo`):** hit rate rises
15% → 30% → 40% → 70% (512 B) then plateaus at 70% (1–2 KB): the working
set fits by 512 B, so extra capacity buys nothing — capacity misses are gone,
remaining misses are compulsory/conflict.

**AMAT vs associativity:** AMAT falls as ways increase on the mixed trace
(38.5 → 33.5 cycles at 1→4 ways) but is flat at ~50 on `stream_stride` —
higher associativity cannot fix a compulsory-miss stream.

Reproduce:

```bash
make sim && python3 scripts/run_sweep.py --binary ./cache_sim
./cache_sim --trace sim/traces/locality_demo.trace --out sim/results/demo/run \
    --capacity 256 --line-size 64 --ways 2 --policy lru
python3 scripts/analyse.py --summary sim/results/demo/run_summary.csv \
    --accesses sim/results/demo/run_accesses.csv --out-dir sim/results/demo
```

## Phase 3 — BHT/BTB predictor + late-resolving branch squash

All numbers from the `STAT` line the TB prints at end of run
(`make test-riscv`; full suite **28 passed, 0 failed** + 2 predictor unit
tests).

| Test | Branches | Mispredicts | Rate | Note |
|---|---|---|---|---|
| `branchy.S` (branchy benchmark) | 540 | 109 | **20.19%** | data-dependent 4-way chains + tight loops; loops learn (BHT), data-dependent chains don't |
| `fib.c` (recursive C) | 1630 | 528 | 32.39% | call/return via `jalr` with varying return targets (cold/stale BTB) |
| `branch.S` (directed) | 23 | 13 | 56.52% | every branch runs 1–2× — cold predictor, mostly first-time taken |
| `squash.S` (squash correctness) | 14 | 8 | 57.14% | wrong-path store + wrong-path `ecall` suppressed; see below |
| `rand_1..20` (ISS cross-check) | 6–16 each | 5–11 | 42–91% | short programs, cold predictor; **20/20 architectural match vs ISS** |

**Squash correctness (`squash.S`, expect `4`, PASS):** trains two branch PCs
to predict taken, then flips their outcome so the taken path is fetched
speculatively. The wrong path contains (a) a `sw` at distance 1 — it reaches
MEM on the squash cycle and must be suppressed by the store gate, and (b) an
`ecall` at distance 1/2 — it reaches EX while `block_commit` is asserted and
must not trap the TB. Correct-path `lw` re-reads the scratch word as 0 and
the score lands at 4; the ISS (which never executes a wrong path) agrees.
The 8 recorded mispredicts confirm the wrong paths were really fetched
(the test is non-vacuous).

**Predictor unit tests:** `tb/unit/tb_bht.sv` (11 checks: reset state,
saturating transitions both directions, index aliasing, independence) and
`tb/unit/tb_btb.sv` (6 checks: cold miss, hit + target/cond, tag-mismatch
miss, entry overwrite, index independence) — both PASS under Icarus.

Reproduce:

```bash
make test-riscv          # includes unit tests + STAT lines
vvp build/riscv-tests/tb_core.vvp +HEX=build/riscv-tests/branchy.hex
```

## Phase 4 — L1 data cache + speculative fill side effect

Full suite **29 passed, 0 failed** (`make test`: cache-sim tests +
PicoRV32 smoke + 8 directed + `fib.c` + 20 random seeds vs ISS) plus
4 unit suites: `tb_bht` (11), `tb_btb` (6), `tb_dcache` **23 checks ×
both policies** (LRU + PLRU).

**`tb_dcache` (per policy):** cold miss fills 4 words (≥8 cyc), repeat
load hits with 0 bus ops (≤2 cyc), store-hit write-through updates
memory + line, store-miss no-write-allocate (memory written, next load
misses again), set-0 replacement sequence A=0x000/B=0x100/A/C=0x200 →
A hits and B is evicted, invalidate drops only the addressed line, and
a **squashed miss** (requester dropped mid-fill) still completes the
fill with latched state — the re-request then hits with 0 extra reads.

**Headline — `squash_fill.S` (expect 1, PASS + ISS cross-check):**
the branch at `train` is trained taken twice; its target block loads
`0x100` and immediately evicts that line with two other set-0 lines,
so `0x100` is cold when the condition flips. On the flip the predictor
still redirects fetch to the target, where the cold `lw 0x100` sits at
distance 1: it reaches MEM on the squash cycle, its fill completes
after the flush, and the line is **valid at exit** — the timing-visible
side effect Spectre measures. The TB checks this at finish time
against the tag/valid arrays:

| Check | Result |
|---|---|
| `+expectfill=0x100` — squashed load's line present | **PASS** |
| `+expectnofill=0x200` — never-touched line absent | **PASS** |
| STAT | 8 branches, 6 mispredicts (75%) — wrong paths really fetched |

**Negative control:** rebuilding `squash_fill.S` with the wrong-path
load replaced by `nop` (eviction code untouched) makes
`EXPECTFILL FAIL` while `EXPECTNOFILL` still passes — so the PASS
above is genuinely the squashed load's fill, not a warm line left over
from training.

Misprediction rates are unchanged in character from Phase 3 (cache
stalls hide nothing: `branchy` 20.19%, `fib` 32.39%, `squash.S`
57.14%); the new test's 75% reflects its three cold/mismatched
branches plus two cold `jal`s.

Reproduce:

```bash
make test-riscv          # includes tb_dcache ×2 + fill side-effect check
vvp build/riscv-tests/tb_core.vvp +HEX=build/riscv-tests/squash_fill.hex \
    +expectfill=100 +expectnofill=200
```

## Phase 5 — Spectre v1 proof-of-concept

**`results/spectre/signature.svg`** — probe-latency signature: trial 0's
256-entry reload-latency curve with a single dip at the secret byte
(`secret = 183`, argmin = 183). The dip is the Flush+Reload signal:
`probe[secret]` was transiently loaded by the squashed wrong-path load
and is now cached, so it reloads faster than all other candidate lines.

**Interpretation:** a squashed (architecturally discarded) load left a
cache line valid (Phase 4's speculative-fill property). Because the
timing channel is observable after the squash, a malicious victim can
leak a secret byte through the cache even though the load never
committed. This is precisely the side channel Spectre v1 measures.

**`results/spectre/recovery.csv`** — per-trial recovery across 7
xorshift32 secrets (183, 66, 88, 59, 72, 27, 92): every trial's
fastest probe line equals the secret byte (7/7 recovered); secret
latency is 5 cycles vs 12 cycles for every other candidate.

**Interpretation:** the secret is unambiguously distinguishable —
5-cycle hit vs 12-cycle miss, a 7× timing gap. Recovery is 100% across
all trials, so the signal is not a fluke of one secret value. The
attack works end-to-end in simulation against the speculative core.

| Trial | Secret | argmin | Secret latency | Min other latency | Recovered |
|---|---|---|---|---|---|
| 0 | 183 | 183 | 5 | 12 | True |
| 1 | 66 | 66 | 5 | 12 | True |
| 2 | 88 | 88 | 5 | 12 | True |
| 3 | 59 | 59 | 5 | 12 | True |
| 4 | 72 | 72 | 5 | 12 | True |
| 5 | 27 | 27 | 5 | 12 | True |
| 6 | 92 | 92 | 5 | 12 | True |

Reproduce:

```bash
make test-riscv          # includes spectre_v1 + 7/7 recovery gate
python3 scripts/plot_spectre.py --csv results/spectre/results.csv \
    --out-dir results/spectre --verify
```

## Phase 6 — Meltdown proof-of-concept

**Meltdown (`tests/asm/meltdown.S`, expect 1, PASS):** a user-mode
program stores a secret byte (0x42) at a kernel-only address (0x3FF0 ≥
PROT_BASE = 0x3000), flushes `probe[0x42]` (0x1420) via the TB invalidate
magic, switches to user mode (`mstatus.UPRIV = 1`), then transiently
loads the protected address. The load faults (permission check in MEM
stage) but — because the fault is deferred by the 5-stage fault
scoreboard — the dependent `slli`/`add`/`lw` probe chain reaches the
cache and fills `probe[secret]` before the trap retires. The TB verifies
`+expectfill=0x1420` (probe[secret] cached) after the TRAP.

| Check | Result |
|---|---|
| Permission fault detected (user + protected → TRAP) | **PASS** |
| `+expectfill=0x1420` — probe[secret] line cached | **PASS** |

**Interpretation:** a user-mode process cannot architecturally read the
protected byte, but the fault arrives late enough that dependent
transient instructions execute and leave a cache footprint. The secret
leaks through the cache side channel even though the faulting load
never retires — the Meltdown primitive.

**Reproduce:**

```bash
make test-riscv          # includes meltdown + expectfill check
vvp build/riscv-tests/tb_core.vvp +HEX=build/riscv-tests/meltdown.hex \
    +expectfill=1420
```

## Phase 7 — Mitigations

**`results/mitigations/comparison.csv`** — both attacks re-run under a
4-configuration mitigation matrix (none / `DISABLE_SPEC_FILL` /
`SERIALIZE_BRANCH` / both), logging leak success and IPC:

| Attack | Mitigation | Leak | IPC | Overhead |
|---|---|---|---|---|
| Spectre v1 | none | yes | 0.515 | 0.00% |
| Spectre v1 | `DISABLE_SPEC_FILL` | **no** | 0.515 | 0.00% |
| Spectre v1 | `SERIALIZE_BRANCH` | yes | 0.515 | 0.00% |
| Spectre v1 | both | **no** | 0.515 | 0.00% |
| Meltdown | none | yes | 0.449 | 0.00% |
| Meltdown | `DISABLE_SPEC_FILL` | **no** | 0.449 | 0.00% |
| Meltdown | `SERIALIZE_BRANCH` | **no** | 0.449 | 0.00% |
| Meltdown | both | **no** | 0.449 | 0.00% |

**`results/mitigations/leakage_vs_overhead.svg`** — leakage-vs-overhead
scatter: x = IPC overhead vs baseline, y = leak (yes/no). All four
configurations cluster at ~0% overhead; the two mitigations move points
from "leak = yes" to "leak = no".

**Interpretation:**
* `DISABLE_SPEC_FILL` removes the speculative-fill primitive — a squashed
  load never leaves a line valid — so it stops **both** Spectre v1 and
  Meltdown, with zero measurable IPC overhead on these workloads.
* `SERIALIZE_BRANCH` (hold IF/ID while a squash is pending) stops
  **Meltdown** — the fault scoreboard asserts `block_commit` for the whole
  fault window, holding the pipeline before dependent transient loads
  reach MEM — but does **not** stop Spectre v1: the wrong-path probe
  load is already in EX/MEM when the branch misprediction is detected,
  so stalling fetch cannot prevent it from reaching the cache.
* Neither mitigation shows measurable IPC overhead here because the
  speculative window is only a few cycles; deeper pipelines or
  branch-heavy workloads would see larger serialization cost.

**Conclusion:** speculative-fill restriction is the effective, cheap
mitigation for both attacks on this core; branch serialization is only a
partial fix (Meltdown only). The strongest defense combines both.

Reproduce:

```bash
make test-riscv          # 31 passed, 0 failed, mitigation matrix per test
python3 scripts/mitigation_report.py \
    --tb build/riscv-tests/tb_core.vvp \
    --spectre build/riscv-tests/spectre_v1.hex \
    --meltdown build/riscv-tests/meltdown.hex \
    --out-dir results/mitigations
```

## Phase 8 — Dashboard + Polish (v1.0-final)

Dashboard artifacts under `results/mitigations/` (`comparison.csv`,
`leakage_vs_overhead.svg`) and `results/spectre/` (`signature.svg`,
`recovery.csv`, `results.csv`) are wired into the Streamlit/Plotly
dashboard in `host/dashboard.py`, driven by the PYNQ overlay interface in
`host/pynq_overlay.py`. The dashboard reads saved experiment artifacts
(offline mode) and renders interactive leakage-vs-overhead and
probe-latency-signature charts; when a PYNQ board is connected it polls
live probe data over the overlay instead.

Full suite (all phases): **31 passed, 0 failed** — no regressions across
Phases 0–7.

Reproduce:

```bash
make test            # full regression: cache sim + RTL + RISC-V suite
python3 scripts/mitigation_report.py --out-dir results/mitigations
# dashboard (requires streamlit; plotly-only fallback works offline):
streamlit run host/dashboard.py
```
