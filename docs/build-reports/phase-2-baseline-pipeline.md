# Build report — Phase 2: Baseline speculative 5-stage pipeline

**Date:** 2026-11-10
**Branch:** `feat/baseline-pipeline` → `develop`
**PR:** (this PR)
**Depends on:** Phase 1 (PR #13, tag `v0.1-cache-sim`)

## Goals (from spec §5, Phase 2 + deliverable 2)

- [x] RV32I 5-stage pipeline (fetch/decode/execute/memory/writeback) in
      SystemVerilog, derived from the PicoRV32 fork's decode semantics
- [x] Baseline speculation: predict-not-taken branches resolved in EX with
      flush of younger stages; JAL/JALR redirect from EX
- [x] Hazard handling: 1-cycle load-use interlock, full EX/MEM/WB forwarding
      (incl. store data), write-first regfile
- [x] Bus: combinational-ready I-side, registered 1-wait-state D-side slave
- [x] `cycle`/`instret` (+ machine aliases) CSRs, read-only under writes
- [x] Testbench + **tests: directed assembly (5), C smoke (`fib(12)=144`),
      randomized programs cross-checked against a Python RV32I ISS**
- [x] `docs/architecture.md` FSM→5-stage mapping table filled

## What was done

1. **New RTL** `rtl/core/`: `core_pkg.sv` (pipeline types/ALU/WB enums),
   `fetch.sv` (skid/outstanding FSM), `decode_comb.sv` + `decode.sv`,
   `regfile.sv`, `execute.sv` (forwarding + branch resolve + CSR req),
   `mem_stage.sv` (byte lanes, hold), `writeback.sv`, `csr.sv`,
   `core5.sv` (hazard unit: `load_use`, `take`, `redirect`).
2. **Testbench** `tb/integration/tb_core.sv`: `+HEX` program load,
   zero-initialized memories (FBRAM-like, matches ISS), magic-signature
   word store to `0xFFFF0000`, TRAP/TIMEOUT detection, `+trace` debug
   (retire PC, regfile writes, d-bus ops, full per-cycle pipeline state).
3. **Test infrastructure**:
   - `tests/link.ld`, `tests/start.S` (CRT0: stack @0x4000, bss clear,
     publish `a0` to magic address)
   - `tests/asm/{arith,branch,loadstore,hazard,csr}.S` — self-checking
     (`# expect: 1` parsed by the runner); `hazard.S` includes a targeted
     regression for the WB→EX-forward-through-MEM-stall bug found below
   - `tests/c/fib.c` — recursive C with stack calls (`fib(12) = 144`)
   - `tests/asm/iss.py` — RV32I ISS (magic-store convention, validates
     random programs; also cross-checks directed tests)
   - `tests/asm/gen_random.py` — constrained-random generator (forward-only
     branches, safe memory, all regs initialized)
   - `tests/run_riscv_tests.sh` — builds with `riscv-none-elf-gcc
     -march=rv32i_zicsr`, converts via `tests/bin2hex.py`, runs RTL vs
     expected and ISS vs expected
4. **Build/CI**: `make test-riscv` (wired into `make test`), new CI job
   `riscv-tests` (Icarus + cached xpack toolchain v15.2.0-1), Python lint
   extended to the new scripts.

## Notable bugs caught by testing

1. **WB→EX forward lost during MEM stall (RTL, real bug).** `fib` stored to
   wrong addresses (`sp` stale by one frame). Root cause: `mem_stage` cleared
   `memwb.valid` while `hold` was asserted, so the instruction frozen in EX
   lost its WB forward source on the stall-release cycle and captured a stale
   decode-time operand snapshot. Fix: keep the WB slot content stable during
   `hold` (regfile re-write is idempotent) and gate `csr.retire` to the first
   cycle of each WB residency (`wb_first` in `core5.sv`). Added a directed
   regression (producer + 3 stores across the stall) to `hazard.S`.
2. **ISS `imm_s` sign-extension** used `-0x2000` instead of `-0x1000`
   (and `imm_b` tested the wrong sign bit) — caught because RTL and ISS
   diverged on `sw t0, -16(a1)`; RTL was right.
3. **Test expectation errors** (both RTL and ISS agreed they fail — the
   tests were wrong): `arith.S` xori expected value, `loadstore.S` byte-2 of
   `0x12345678` is `0x34` not `0x45`; `sltiu` needs an immediate.
4. **TB `dmem` started as X** while the ISS models memory as zero (and FPGA
   BRAM initializes to 0) — random tests loading untouched memory produced
   `MAGIC 0xxx…`. Fixed by zero-filling both memories in the TB initial.
5. **Runner robustness**: missing-MAGIC runs aborted the whole script under
   `pipefail` instead of reporting FAIL (`grep` exit status now absorbed);
   `csrr` tests need `-march=rv32i_zicsr`.

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Directed asm (5) + ISS cross-check | `make test-riscv` | **PASS** (hazard includes stall-forward regression) |
| C smoke `fib(12)` | `make test-riscv` | PASS `magic=0x90` (144) |
| Randomized vs ISS (20 seeds) | `make test-riscv` | **20/20 PASS** |
| Full suite | `make test-riscv` | **26 passed, 0 failed** |
| Phase 0/1 gates | `make test` | cache-sim 16/16 + picorv32 smoke PASS |
| Toolchain | `riscv-none-elf-gcc --version` | xpack 15.2.0 (CI: cached x64 tarball) |

## Artifacts

- `rtl/core/*.sv` (10 files), `tb/integration/tb_core.sv`
- `tests/{link.ld,start.S,bin2hex.py,run_riscv_tests.sh}`,
  `tests/asm/*.S` + `iss.py` + `gen_random.py`, `tests/c/fib.c`
- `docs/architecture.md` — stage mapping + Phase 2 control decisions
- `Makefile` (`test-riscv`), `.github/workflows/ci.yml` (`riscv-tests` job)

## Issues / risks

- Uninitialized registers start as X in RTL (RISC-V leaves regfile reset
  values unspecified; ISS starts at 0). Tests avoid reading before writing;
  gen_random inits all GPRs. If a future test needs determinism, reset the
  regfile or document the constraint.
- Icarus emits benign "constant selects in always_*" warnings (sensitivity
  lists include extra bits — simulation-safe); no Verilator available locally,
  lint remains skipped.
- Phase 3 will retime fetch around BHT/BTB; `fetch.sv`'s skid/outstanding
  invariants and the `+trace` hooks are the reference for validating it.

## Exit criteria for next phase

Phase 3 (BHT/BTB + scoreboard) starts once this PR squash-merges to
`develop`, promotes to `main`, and is tagged `v0.2-core-pipeline`.
