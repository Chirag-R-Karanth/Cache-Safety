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

## Planned result artifacts (later phases)

- **Phase 3:** misprediction rate on branchy benchmark; squash correctness.
- **Phase 4:** speculative-fill side-effect test (squashed load visible in tag array).
- **Phase 5:** probe latency vs byte value (256 points, one dip) + recovery rate.
- **Phase 6:** Meltdown leak success rate U/S modes; first live FPGA data.
- **Phase 7:** mitigation comparison — leak rate × IPC/cycle overhead.
- **Phase 8:** dashboard screenshots, final consolidated writeup.
