# Results

> Every chart is generated from saved raw data under `sim/results/`
> (see `docs/ANALYSIS_PLAYBOOK.md` for the reproducibility rules).

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

## Planned result artifacts (later phases)

- **Phase 5:** probe latency vs byte value (256 points, one dip) + recovery rate.
- **Phase 6:** Meltdown leak success rate U/S modes; first live FPGA data.
- **Phase 7:** mitigation comparison — leak rate × IPC/cycle overhead.
- **Phase 8:** dashboard screenshots, final consolidated writeup.
