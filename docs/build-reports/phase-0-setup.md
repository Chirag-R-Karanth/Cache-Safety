# Build report — Phase 0: Setup

**Date:** 2026-11-10
**Branch:** `feat/phase0-setup` → `develop`
**PR:** _filled in after creation_
**Tag:** `v0.0-setup`

## Goals (from spec §5, Phase 0)

- [x] Repo scaffold with CI skeleton
- [x] Toolchain verified (Icarus "hello world"-equivalent sim)
- [x] PicoRV32 forked into `rtl/core/`, simulating standalone in Icarus
- [x] `docs/threat-model.md` written
- [x] Teammate parallel tracks unblocked (sim + dashboard consume CSV/JSON)

## What was done

1. **Branch hygiene:** reconciled `main` (cache-sim work) with scaffolding
   branch; created `develop`; feature-branch workflow per spec §2.
2. **Restructured to spec layout:** `sim/{src,tests,traces,results}`,
   `rtl/core/picorv32/`, `tb/unit/`, `docs/build-reports/`, `.github/workflows/`.
   Spec master prompt preserved as `docs/SPEC.md`.
3. **PicoRV32 fork:** vendored upstream @ `ef203c2` (`picorv32.v`, `COPYING`,
   reference `testbench_ez.v`) with `FORK.md` documenting why + planned mods.
4. **Self-checking smoke testbench** `tb/unit/tb_picorv32.sv`: runs the
   reference increment loop, asserts counter word > 3, traps are failures.
5. **CI** `.github/workflows/ci.yml`: cache-sim build+tests, Icarus RTL smoke,
   Python syntax lint — on every push/PR.
6. **Docs:** threat model (in/out of scope claims table), architecture stub,
   results stub, rewritten README, `Makefile`, `requirements.txt`, `LICENSE` (MIT),
   `.gitignore`.

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Cache sim builds (strict flags) | `g++ -std=c++17 -O2 -Wall -Wextra -Wpedantic sim/src/cache.cpp` | pass, 0 warnings |
| Cache sim unit tests | `python3 -m unittest discover -s sim/tests -v` | **5/5 OK** |
| PicoRV32 fork under Icarus | `iverilog -g2012 … && vvp tb_picorv32.vvp` | **PASS: counter=90 after 2010 cycles** |
| Design-space sweep script | `python3 scripts/run_sweep.py --binary ./cache_sim` | wrote `comparison.csv` + SVG chart |
| Full gate | `make test` | pass |

## Artifacts

- `rtl/core/picorv32/` (fork + FORK.md), `tb/unit/tb_picorv32.sv`
- `docs/threat-model.md`, `docs/SPEC.md`, `docs/architecture.md`, `docs/results.md`
- `sim/results/sweep/comparison.csv`, `hit-rate-comparison.svg` (regenerated)

## Issues / risks

- No local Verilator and no passwordless sudo → RTL lint runs in CI only
  (Ubuntu runner installs `iverilog` via apt); local gate is Icarus.
- RISC-V GNU toolchain not yet installed — required from Phase 2 (directed
  asm tests) and Phase 5 (attack C code). Planned: prebuilt toolchain tarball.
- PYNQ-Z1 vs Z2 unresolved (open question in spec) — only affects Phase 7/8
  `.xdc`; defaulting to Z1 until board revision confirmed.

## Exit criteria for next phase

Phase 1 may start once this PR is squash-merged and `main` is green.
