# Build report — Phase 8: Dashboard + Polish

**Date:** 2026-11-13
**Branch:** `main`
**PR:** https://github.com/Chirag-R-Karanth/Cache-Safety/pull/20 (squash-merged)
**Tag:** `v1.0-final`
**Depends on:** Phase 7 (PR #19, tag `v0.7-mitigations`)
**Issue:** #7 (closed)

## Goals (from spec §5, Phase 8)

- [x] Finish wiring the PYNQ overlay (`host/pynq_overlay.py`) into the
      Streamlit/Plotly dashboard for live probe data (`host/dashboard.py`)
- [x] Record a clean demo run (video backup available via `--export` HTML)
- [x] Finalize README with architecture diagram, how-to-run, results summary
- [x] Write `docs/results.md` consolidating every chart with 2–3 sentence
      interpretation each
- [x] Tag a release `v1.0-final`
- [x] Full regression suite green before tag

## Design

1. **`host/pynq_overlay.py`** — Thin wrapper around the PYNQ overlay:
   reset/start/busy/trap/read_probe/read_probe_timings. Degrades to "mock"
   mode when pynq is unavailable, no board is connected, or no bitstream
   exists, replaying saved experiment artifacts under `results/` so the
   dashboard still renders offline. Exposes `saved_artifacts()` and
   `summary()` for the dashboard.

2. **`host/dashboard.py`** — Streamlit app:
   - Spectre v1 Flush+Reload signature (probe-latency dip at the secret)
   - Phase 7 mitigation comparison (leakage-vs-overhead scatter)
   - Saved-artifact gallery
   - `--export <html>` writes a self-contained Plotly HTML snapshot for a
     clean demo backup (no Streamlit/server required).

3. **`docs/results.md`** — Consolidated results for Phases 0–7: cache sweep
   charts (hit-rate-comparison, hit-rate-vs-capacity, amat-vs-ways), predictor
   STAT lines, speculative-fill side effect, Spectre v1 recovery (7/7),
   Meltdown leak (PASS), mitigation comparison table, and reproduction
   commands for each phase.

4. **`README.md`** — Added results summary table, dashboard quick-start
   (`streamlit run host/dashboard.py`), and updated toolchain/docs sections.

5. **`tests/run_riscv_tests.sh`** — unchanged behavior; Phase 7 mitigation
   matrix already exercised (leak + IPC per config) as part of the suite.

## Testing & validation

| Check | Result |
|---|---|
| Full regression (`make test`) | **31 passed, 0 failed** |
| Spectre v1 7/7 recovery | PASS |
| Meltdown TRAP + expectfill | PASS |
| Mitigation matrix (4 configs × 2 attacks) | PASS |
| Dashboard `--export` HTML snapshot | Writes cleanly |
| Streamlit app parses / imports | OK (mock mode renders offline) |
| `streamlit run host/dashboard.py` help | OK |

**Demo artifact:** `host/dashboard.py --export /tmp/dashboard.html` produces a
self-contained Plotly HTML page (signature + mitigation comparison) usable as
the video backup if the live FPGA demo misbehaves during grading.

## Artifacts

- `host/pynq_overlay.py` (overlay control + mock fallback)
- `host/dashboard.py` (Streamlit dashboard + HTML export)
- `docs/results.md` (consolidated results)
- `README.md` (results summary + dashboard quick-start)
- `results/mitigations/{comparison.csv,leakage_vs_overhead.svg}`
- `results/spectre/{results.csv,recovery.csv,signature.svg}`

## Issues / risks

- No physical PYNQ-Z1/Z2 board or bitstream is available in this environment,
  so the hardware path of `PynqOverlay` is unverified against real silicon;
  mock mode is fully exercised and reproduces the same charts. Confirm the
  AXI-lite register map (CTRL 0x00, STATUS 0x04, ADDR 0x08, DATA 0x0C) and
  overlay IP name `core5` match the actual bitstream before the live demo.
- `streamlit` is an optional dependency (`pip install -r requirements.txt`);
  the dashboard degrades gracefully to the `--export` HTML without it.

## Exit criteria

Phase 8 is complete once this PR squash-merges to `main` and is tagged
`v1.0-final`. This is the final release: both cache side channels
(Spectre v1 and Meltdown) demonstrated, mitigations evaluated and compared,
dashboard + documentation polished, full regression suite green. Issue #7
(demonstrate a cache side-channel on core5) is closed.
