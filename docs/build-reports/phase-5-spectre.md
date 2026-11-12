# Build report — Phase 5: Spectre v1 proof-of-concept

**Date:** 2026-11-12
**Branch:** `main`
**PR:** https://github.com/Chirag-R-Karanth/Cache-Safety/pull/17 (squash-merged)
**Tag:** `v0.5-spectre-poc`
**Depends on:** Phase 4 (PR #16, tag `v0.4-l1-dcache`)
**Issue:** #7 (closed)

## Goals (from spec §5, Phase 5)

- [x] Demonstrate an end-to-end Spectre v1 Flush+Reload attack on core5
- [x] Reuse the Phase 4 speculative-fill side effect (squashed load leaves a
      line valid) as the timing channel
- [x] Add a TB invalidate port (store to 0xFFFF0001 → 1-cycle pulse of
      `inval_valid`/`inval_addr`) for Flush+Reload probe eviction
- [x] Export probe latencies as `RES <idx> <latency>` lines from the TB on
      completion; runner converts to CSV and runs `scripts/plot_spectre.py`
- [x] Verify every trial recovers the secret (dip at `b == secret`)

## Design

1. **`tests/asm/spectre_v1.S`** — the victim holds a secret byte at `0x0400`,
   derives `probe_ptr = probe + secret*16`, mistrains the bounds-check branch
   as not-taken (2 evals keep the 2-bit BHT weakly-not-taken), then flips with
   an OOB index. Because the core is in-order with late-resolve squash, the
   wrong path is exactly one instruction: `lw probe[secret]` at distance 1,
   which fills the `probe[secret]` line speculatively. Each trial sweeps all 256
   candidates `probe[b]`, flushing the candidate first (store to
   `0xFFFF0001`), timing the reload with `mcycle`, and storing word0=secret and
   words 1..256=latency[b] in a 257-word block at `0x2000`. N=7 trials with
   xorshift32 secrets.
2. **`tb/integration/tb_core.sv`** — magic store split: `0xFFFF0000` → finish +
   stats (unchanged); `0xFFFF0001` → pulse `inval_valid`/`inval_addr` (Flush
   +Reload probe drop). `inval_valid` defaults to 0 each cycle (one-cycle
   pulse). New `finish_dump` task emits `RES <i> <hex>` for a dumpable dmem
   region (`+DUMPADDR=`/`+DUMPWORDS=` plusargs), called from `finish_stats`.
3. **`scripts/plot_spectre.py`** — parses the CSV (`trial,secret,b,latency`),
   verifies the fastest probe line in every trial is the secret byte
   (`argmin == secret` and strictly faster than all others), renders the
   signature plot (`signature.svg`) and writes `recovery.csv`. `--verify`
   exits non-zero unless all trials recover.
4. **`tests/run_riscv_tests.sh`** — `spectre_v1` gets `+TIMEOUT=2000000`
   `+DUMPADDR=2000 +DUMPWORDS=1799`; RES lines are converted to
   `results/spectre/results.csv`; `plot_spectre.py --csv ... --verify` gates
   the suite result. `printf | grep -q` replaced with herestrings to avoid
   SIGPIPE races under `pipefail`.
5. **`.github/workflows/ci.yml`** — installs `matplotlib` for the signature
   plot and adds `scripts/plot_spectre.py` to the Python syntax-check step.

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Spectre v1 attack (magic) | `make test-riscv` | **PASS** (`magic=1`) |
| Secret recovery all trials | `plot_spectre.py --verify` | **7/7 recovered** (5 cyc hit vs 12 cyc miss) |
| Signature plot + recovery CSV | `results/spectre/` | written (`signature.svg`, `recovery.csv`) |
| Full suite (directed + ISS + 20 random) | `make test-riscv` | **30 passed, 0 failed** |
| Phase 4 regression (squash_fill) | `make test-riscv` | **EXPECTFILL/EXPECTNOFILL PASS** |
| Python syntax check | CI step | `plot_spectre.py` included |

## Artifacts

- `tests/asm/spectre_v1.S` (Spectre v1 victim, Flush+Reload sweep)
- `scripts/plot_spectre.py` (signature plot + recovery verification)
- `tb/integration/tb_core.sv` (flush magic `0xFFFF0001`, `RES` dump)
- `tests/run_riscv_tests.sh` (spectre_v1 flags, RES→CSV→plot gate)
- `.github/workflows/ci.yml` (matplotlib, plot source in syntax check)
- `results/spectre/{results.csv,signature.svg,recovery.csv}` (evidence)

## Issues / risks

- The attack relies on the Phase 4 speculative-fill property: a squashed
  wrong-path load's fill completes and leaves the line valid. If that
  primitive is removed or gated, Phase 5 silently produces no timing dip.
- Flush+Reload here uses an exact single-line invalidate; a set/way
  associate mismatch between flush address and probe address would hide the
  dip. Verified by the 7/7 recovery across 7 distinct xorshift32 secrets.
- `RES` dump region (`0x2000`, 1799 words = 7 × 257) must not collide with
  the probe array (`0x1000`) or secret array (`0x0400`).

## Exit criteria

Phase 5 is complete once this PR squash-merges to `main` and is tagged
`v0.5-spectre-poc`. This closes issue #7 (demonstrate a cache side-channel
on core5).
