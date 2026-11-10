# Results

> Status: **Phase 0 baseline** — no attack results yet. Per-phase numbers and
> charts land here and in [build reports](build-reports/) as phases complete.
> Every chart is generated from saved raw data under `sim/results/` or
> `results/` (see `docs/ANALYSIS_PLAYBOOK.md` for the reproducibility rules).

## Phase 0 (baseline)

| Check | Result |
|---|---|
| Cache sim builds (`g++ -Wall -Wextra -Wpedantic`) | pass |
| Cache sim unit tests (5) | pass |
| PicoRV32 fork standalone Icarus smoke test | pass (see build report) |

## Planned result artifacts

- **Phase 1:** hit-rate curves, AMAT vs associativity/line-size sweeps (2+ traces).
- **Phase 3:** misprediction rate on branchy benchmark; squash correctness.
- **Phase 4:** speculative-fill side-effect test (squashed load visible in tag array).
- **Phase 5:** probe latency vs byte value (256 points, one dip) + recovery rate.
- **Phase 6:** Meltdown leak success rate U/S modes; first live FPGA data.
- **Phase 7:** mitigation comparison — leak rate × IPC/cycle overhead.
- **Phase 8:** dashboard screenshots, final consolidated writeup.
