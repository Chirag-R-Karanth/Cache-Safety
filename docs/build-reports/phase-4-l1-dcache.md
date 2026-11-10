# Build report — Phase 4: L1 data cache + speculative fill side effect

**Date:** 2026-11-10
**Branch:** `feat/l1-dcache` → `develop`
**PR:** https://github.com/Chirag-R-Karanth/Cache-Safety/pull/16 (squash-merged, `28b9778`)
**Tag:** `v0.4-l1-dcache` (deviation: SPEC §test-matrix lists
`v0.4-spectre-poc` for what is actually Phase 5; tags follow phase order —
noted here and in the PR)
**Depends on:** Phase 3 (PR #15, tag `v0.3-predictor`)
**Issue:** #7 (closed)

## Goals (from spec §5, Phase 4)

- [x] Integrate a set-associative cache into the memory stage
      (configurable ways/line size, LRU + PLRU replacement)
- [x] Explicitly verify that **a load changes cache state even if it is
      later squashed** (spec: "a load changes cache state even if later
      squashed")
- [x] Unit testbenches for the cache (`tb/unit/tb_dcache.sv`, both
      replacement policies)
- [x] Speculative-fill side-effect test in the directed suite
      (`squash_fill.S` + TB `+expectfill`/`+expectnofill` checks)

## Design

1. **`rtl/cache/l1_dcache.sv`** — 16 sets × 2 ways × 16-byte lines by
   default (offset `addr[3:0]`, set `addr[7:4]`, tag `addr[31:8]`),
   `POLICY` parameter selects `replacement_lru.sv` (per-set move-to-front
   stack) or `replacement_plru.sv` ((WAYS−1)-bit heap tree per set).
2. **Write-through, no-write-allocate.** Stores always write the bus
   (the ISS-visible memory image, the TB magic signature and any bus
   observer stay coherent) and byte-merge into the line only on a hit;
   a store miss goes to memory without allocating. Loads fill a whole
   line on miss. This was chosen over write-back specifically so the
   magic signature and random/ISS cross-checks stay valid unmodified.
3. **FSM** `S_IDLE → {S_RESP, S_WT, S_FILL}`: hit latches `rsp_rdata`
   and answers next cycle; fill streams the 4 words then re-serves the
   request as a hit. `mem_stage` keeps its `hold`/`mem_done` contract
   (`mem_done = !is_mem_op || rsp_ready`) so no pipeline protocol
   changed outside the memory path.
4. **Latched-fill FSM — the Phase 4/5 primitive.** Line identity
   (base/set/tag/way) is captured when the miss is entered. Once
   `S_FILL` starts, the FSM runs to completion even if `req_valid`
   drops — which is what the late-resolve squash does to the wrong-path
   load (EX/MEM cleared, pipeline continues). The fill then sets
   `valid`/`tag` from the latched state; the squashed instruction's
   `rsp_ready` pulse is never consumed (MEM/WB was cleared). Net
   effect: **the line is valid at exit although the load never
   committed** — the timing-visible side effect Spectre measures.
5. **Squash-cycle gating stays load-transparent.** The wrong-path load
   is always in its *first* MEM cycle on the squash cycle (Phase 3's
   in-order age argument), so `req_valid = is_mem_op && !(squash &&
   is_store)` suppresses wrong-path stores before they reach the cache
   without ever blocking an older in-flight fill.
6. **Replacement updates** fire on served hits and on fill completion,
   always with the *latched* fill set/way — after a squash the live
   `req_addr` already belongs to another instruction.
7. **Invalidate port** (`inval_valid`/`inval_addr` → tag compare, all
   ways, applied last in the state update) added through
   `mem_stage`/`core5`/`tb_core` for the Phase 5 Flush+Reload probe.

## What was done

1. **New RTL**: `rtl/cache/replacement_lru.sv`,
   `rtl/cache/replacement_plru.sv`, `rtl/cache/l1_dcache.sv`.
2. **Modified RTL**: `mem_stage.sv` (now request/response interface
   toward the cache; store lane replication moved inside; load
   extraction from `rsp_rdata`; invalidate ports),
   `core5.sv` (`inval_valid`/`inval_addr` ports wired through).
3. **Tests**:
   - `tb/unit/tb_dcache.sv` — 23 checks per policy: miss→fill→hit
     data + latency, hit = 0 bus ops, store-hit write-through
     coherence, store-miss NWA, set-0 replacement (A/B/A/C → A hits,
     B evicted), invalidate selectivity, and a **squashed-miss** test
     (requester dropped mid-fill → bus goes quiet → re-request hits
     with 0 extra reads). Compiled twice: default LRU and
     `-DPLRU_TEST` (Icarus has no `-P` parameter override).
   - `tests/asm/squash_fill.S` (expect `1`, ISS-checked): branch
     trained taken ×2; target block loads `0x100` then evicts it with
     two other set-0 lines (`0x000`, `0x300`) so it is cold at the
     flip; flip → wrong-path `lw 0x100` at distance 1 → fill completes
     after the squash. Correct fall-through does a real `lw 0x000`
     (must read 0) and stores magic 1.
   - `tb_core.sv`: `+expectfill=<hex>` / `+expectnofill=<hex>` plusargs
     check the cache tag/valid arrays at finish (`EXPECTFILL` /
     `EXPECTNOFILL` PASS/FAIL lines, printed from `finish_stats` on
     every exit path); `inval_*` ports tied to pokable regs.
   - runner: compiles the cache RTL into `tb_core`, runs `tb_dcache`
     under both policies in the unit-test section, and gives
     `squash_fill` a second run with `+expectfill=100
     +expectnofill=200`, failing the suite if either line is not PASS.
4. **Docs**: `architecture.md` (full L1 section replacing the Phase 4
   placeholder), `results.md` (Phase 4 tables + negative control).

## Testing & validation

| Check | Command | Result |
|---|---|---|
| Cache unit tests (LRU + PLRU) | `make test-riscv` | **PASS** (23 checks × 2) |
| Speculative fill side effect | `make test-riscv` | **PASS** (`EXPECTFILL` 0x100 present, `EXPECTNOFILL` 0x200 absent) |
| Negative control (wrong-path load → `nop`) | manual `vvp … +expectfill=100` | `EXPECTFILL FAIL` — eviction works, PASS is non-vacuous |
| Directed asm (8) + ISS cross-check | `make test-riscv` | **PASS** incl. `squash_fill.S` (magic=1) |
| Randomized vs ISS (20 seeds) | `make test-riscv` | **20/20 PASS** |
| Full suite | `make test` | **29 passed, 0 failed** + picorv32 PASS + cache-sim 16/16, exit=0 |

## Notable design points / bugs avoided

1. **No-write-allocate + magic store.** The magic signature is a word
   store to `0xFFFF0000` (set 0, tag `0xFFFF00`). Under NWA it never
   allocates, so it cannot evict the checked `0x100` line on its way to
   finishing the test.
2. **Fill latching.** The live `req_addr`/`req_set` change the moment
   the squash clears EX/MEM; the fill's set/tag/way/base are therefore
   captured at fill start, and replacement updates at fill completion
   use the latched set (`repl_upd_set`), not the live one.
3. **Declarations before use.** `repl_upd*` signals were first written
   below their instantiation; Icarus silently created implicit 1-bit
   nets (would have corrupted set indices). Caught by a port-width
   warning, moved above the generate block.
4. **Test-address aliasing.** First draft used `0x400` as a
   "different set" for the NWA test — `set = addr[7:4]` puts it in
   set 0, where it legitimately evicted the replacement-test lines.
   Traced via a replacement-update dump; moved to `0x440` (set 4).
5. **Vacuity control.** `expectfill` alone could pass if the eviction
   sequence was broken (warm line left from training). The `nop`
   rebuild negative control proves `0x100` is cold before the flip and
   present only because of the squashed load's fill.
6. **Icarus "sorry: constant selects in always_*"** on the
   `store_merged` always_comb — benign (byte-merge reads are
   over-sensitive, not mis-evaluated); full-word store-hit coherence
   verified by `tb_dcache` T3.

## Artifacts

- `rtl/cache/{l1_dcache,replacement_lru,replacement_plru}.sv`
- `rtl/core/{mem_stage,core5}.sv` (cache interface + invalidate ports)
- `tb/unit/tb_dcache.sv`, `tb/integration/tb_core.sv` (fill
  expectations, invalidate regs)
- `tests/asm/squash_fill.S`, `tests/run_riscv_tests.sh`
- `docs/architecture.md`, `docs/results.md`

## Issues / risks

- Architectural state (registers/memory words) still matches the ISS;
  microarchitectural state (cache lines) intentionally does not —
  that divergence *is* the attack surface measured in Phase 5.
- Write-through adds one bus transaction per store; fine at this
  scale, and it keeps DMA-style observers honest for the dashboard.
- `rsp_ready` after a squashed miss is never consumed: by design (the
  instruction is dead), but a future power/flush feature must not wait
  for a response that the pipeline discarded.
- Fill latency (~10 cycles/line with the 1-wait-state slave) stalls
  the requesting instruction only; other instructions flow until they
  themselves need the cache (single-ported).

## Exit criteria for next phase

Phase 5 (Spectre v1 proof-of-concept) starts once this PR
squash-merges to `develop`, promotes to `main`, and is tagged
`v0.4-l1-dcache`.
