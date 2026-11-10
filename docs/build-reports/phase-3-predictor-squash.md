# Build report — Phase 3: BHT/BTB predictor + late-resolving branch squash

**Date:** 2026-11-10
**Branch:** `feat/bht-predictor` → `develop`
**Tag:** `v0.3-predictor` (after merge/promote)
**Depends on:** Phase 2 (PR #14, tag `v0.2-core-pipeline`)

## Goals (from spec §5, Phase 3 + deliverable 2)

- [x] 2-bit saturating-counter BHT + BTB, predict-and-continue fetch
- [x] Scoreboard so younger instructions execute while a predicted branch is
      unresolved (late-resolving branch: squash deferred to WB)
- [x] Squash/recovery on misprediction (flush + redirect, wrong-path
      stores/traps/CSR/training suppressed, speculative loads pass through)
- [x] Misprediction rate on a branchy benchmark (TB `STAT` line)
- [x] Squash correctness confirmed with randomized tests (20 seeds vs ISS)
      + a directed wrong-path store/trap test (`squash.S`)
- [x] Unit testbenches `tb/unit/tb_bht.sv`, `tb/unit/tb_btb.sv`
      (spec test matrix: saturating transitions, aliasing, hit/miss)

## Design

The Spectre v1 requirement is that a mispredicted-path load *executes*
(memory access / cache fill) before the branch recovers. A resolve-at-EX
flush (Phase 2) never lets a wrong-path instruction past EX, so Phase 3
splits resolution from recovery:

1. **Prediction at fetch** (`fetch.sv`): every fetched instruction is
   queried against `bht_2bit.sv` (256 × 2-bit, PC[9:2], weakly not-taken
   reset) and `btb.sv` (64-entry direct-mapped, tagged PC[31:8], `cond`
   flag). `pred_taken = btb_hit && (!cond || bht_taken)`; the next PC
   follows the prediction (`predict-and-continue`). Prediction bits are
   captured into IF/ID (and the skid) alongside the instruction.
2. **Resolve in EX, squash at WB** (`execute.sv` + `scoreboard.sv`): EX
   compares actual vs predicted outcome/target and emits a *resolve record*
   (mispredict + correct target) instead of redirecting. The scoreboard
   queues mispredicts in a 2-stage shift (p1 = branch in MEM, p0 = branch in
   WB). A branch never stalls in MEM (it is never a mem op and `ex_fire`
   guarantees MEM was free at resolve), so EX→MEM→WB is gapless and the
   record fires exactly on the branch's WB cycle: `squash` pulse +
   `squash_target` = pipeline-wide flush/redirect.
3. **Window semantics**: during the 2-cycle window the wrong-path
   instructions keep flowing. `block_commit` (any record in flight) gates
   wrong-path `csr_fire`, `trap_valid` and BHT/BTB training. On the squash
   cycle the wrong-path occupant of MEM is in its *first* MEM cycle (in-order
   age argument), so:
   - **stores** have their `d_valid` suppressed → never commit;
   - **loads** are deliberately *not* gated → their memory access completes
     on the squash cycle (this is the Phase 4/5 Spectre primitive);
   - EX/MEM and MEM/WB clear with priority over `hold`, so the flush cannot
     deadlock behind a waiting bus transaction.
4. **Training** (gated by `!block_commit`): BHT trains on every conditional
   resolve with the actual outcome (2-bit saturating); BTB trains on every
   taken control transfer with the actual target + cond bit.

## What was done

1. **New RTL**: `rtl/predictor/bht_2bit.sv`, `rtl/predictor/btb.sv`,
   `rtl/core/scoreboard.sv`.
2. **Modified RTL**: `core_pkg.sv` (`pred_taken`/`pred_target` in
   `ifid_t`/`idex_t`), `fetch.sv` (predictor instances, next-PC redirect on
   response, prediction capture), `decode.sv` (pass-through),
   `execute.sv` (resolve record + training outputs, `block_commit` gating,
   squash-priority EX/MEM clear; immediate redirect removed), `mem_stage.sv`
   (store gate + squash-priority MEM/WB clear), `core5.sv` (scoreboard
   wiring; `redirect = squash`).
3. **Tests**:
   - `tb/unit/tb_bht.sv` (11 checks), `tb/unit/tb_btb.sv` (6 checks);
   - `tests/asm/branchy.S` — branchy benchmark (expect `0x29c0`, ISS-checked);
   - `tests/asm/squash.S` — wrong-path `sw` (distance 1, MEM-cycle gate) and
     wrong-path `ecall` (distance 1/2, `block_commit` gate) must not commit;
     expect `4`, ISS-checked;
   - `tb_core.sv` now prints `STAT branches=… mispredicts=… rate=…%` on every
     finish path (counters: non-speculative resolve events, squash pulses);
   - runner compiles the new RTL, runs the two unit TBs, echoes STAT lines.
4. **Docs**: `architecture.md` (Phase 3 control decisions + stage notes),
   `results.md` (Phase 3 tables).

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Predictor unit tests (BHT/BTB) | `make test-riscv` | **PASS** (11 + 6 checks) |
| Directed asm (7) + ISS cross-check | `make test-riscv` | **PASS** incl. `squash.S` (magic=4) and `branchy.S` (magic=0x29c0) |
| Randomized vs ISS (20 seeds) | `make test-riscv` | **20/20 PASS** (squash correctness) |
| Full suite | `make test-riscv` | **28 passed, 0 failed** |
| Phase 0–2 gates | `make test` | cache-sim 16/16 + picorv32 PASS + 28 riscv PASS, exit=0 |
| Misprediction rate (headline) | `branchy.S` STAT | **20.19%** (109/540) |
| Misprediction rate (`fib.c`) | STAT | 32.39% (528/1630) |

## Notable design points / bugs avoided

1. **Distance-1 alignment of the squash cycle.** The wrong-path store that
   must be suppressed is always in its *first* MEM cycle exactly when the
   branch's WB squash fires (in-order age + gapless EX→MEM→WB) — so gating
   `d_valid` for stores on `squash` can never suppress a correct-path
   transaction. The argument is recorded in `mem_stage.sv`'s header.
2. **Queue semantics.** Only mispredicts are queued, which makes every p0
   record a firing squash; p1 therefore always dies with p0's flush
   (younger branches behind a mispredict must die with it). A wrong-path
   `j` that resolves during the window (seen in `squash.S` training loops)
   pushes a record that is cleared by the older squash before it can fire —
   without the clear-on-squash rule it would redirect to `fail`.
3. **`wb_first`/instret interaction.** The retiring mispredicting branch
   keeps its WB slot through the squash cycle (regfile write + `instret`
   tick happen during the cycle; the slot clears at the end), so instret
   still ticks exactly once per instruction.
4. **Placeholder expect value**: `branchy.S` initially shipped with
   `# expect: 0`; RTL and ISS both computed `0x29c0` — fixed the comment
   (the cross-check caught it immediately).

## Artifacts

- `rtl/predictor/{bht_2bit,btb}.sv`, `rtl/core/scoreboard.sv`, modified
  `rtl/core/{core_pkg,fetch,decode,execute,mem_stage,core5}.sv`
- `tb/unit/{tb_bht,tb_btb}.sv`, `tb/integration/tb_core.sv` (STAT counters)
- `tests/asm/{branchy,squash}.S`, `tests/run_riscv_tests.sh`
- `docs/architecture.md`, `docs/results.md`

## Issues / risks

- Wrong-path loads that complete during the squash window leave cache
  state behind — intended (Phase 4 depends on it), but means architectural
  equivalence with the ISS holds only for *register/memory-word* state, not
  microarchitectural state. Random tests verify the former.
- `block_commit` also blocks predictor training behind a pending squash, so
  wrong-path branches cannot pollute the BHT/BTB (deliberate; keeps the
  measured mispred rates meaningful).
- Aliasing: BHT is untagged (by design, measured in `tb_bht`); BTB is
  direct-mapped (64 entries) — large code footprints will thrash; fine for
  the small attack/test programs of Phases 4–6.
- Icarus warns "System task cannot be synthesized in always_ff" for the
  TB's `finish_stats` calls — benign (testbench only).

## Exit criteria for next phase

Phase 4 (L1 data cache + speculative fill side effect) starts once this PR
squash-merges to `develop`, promotes to `main`, and is tagged
`v0.3-predictor`.
