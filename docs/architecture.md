# Architecture

> Status: **Phase 3 — BHT/BTB predictor + late-resolving branch squash
> complete.** Phase 4 adds the L1 data cache; see [build reports](build-reports/)
> for incremental updates.

## Overview

```
                 ┌──────────────────────────────────────────────┐
                 │                  soc_top                     │
                 │  ┌─────────┐   ┌──────────┐   ┌───────────┐  │
  instr/data ────┼─▶│  core   │──▶│ l1_dcache│──▶│  memory   │  │
  (AXI-lite /    │  │ (fork)  │   │ (set-assoc│   │  model    │  │
   simple bus)   │  │+scorebd │   │  +repl)  │   │           │  │
                 │  │+predict │   └──────────┘   └───────────┘  │
                 │  └─────────┘        ▲                        │
                 │       │             │ mitigation params      │
                 │  ┌────▼────┐  ┌─────┴──────┐                 │
                 │  │ csr     │  │ mitigations│                 │
                 │  │(cycle,  │  │ fence / cbs│                 │
                 │  │ priv)   │  │ fill-on-cmt│                 │
                 │  └─────────┘  └────────────┘                 │
                 └──────────────────────────────────────────────┘
```

## Base core fork

`rtl/core/picorv32/` vendors PicoRV32 @ `ef203c2` (see `FORK.md`). Phase 0
validates it standalone under Icarus with the reference increment-loop
program (`tb/unit/tb_picorv32.sv`).

### Stage mapping (PicoRV32 FSM → 5-stage pipeline)

| Pipeline stage | PicoRV32 FSM state(s) | Notes |
|---|---|---|
| Fetch | `mem_state` fetch / `reg_prefetched` | `rtl/core/fetch.sv`: predict-and-continue fetch — BHT/BTB queried per fetched instruction (`bht_2bit.sv`, `btb.sv` under `rtl/predictor/`), prediction carried in IF/ID; valid/ready issue handshake, skid register for 1-wait-state responses; redirect/flush on late-resolve squash |
| Decode | decoder `case (instr)` | `decode_comb.sv` (pure decode) + `decode.sv` (ID/EX register, regfile read, flush/hold/load-use-bubble control); forwarding operands and prediction bits captured at ID/EX |
| Execute | `alu_*`, `pcpi` | `execute.sv`: full EX/MEM→EX and MEM/WB→EX forwarding, ALU, branch/jump condition resolve in EX (no immediate redirect); emits a resolve record to the scoreboard + BHT/BTB training; CSR request |
| Memory | `mem_state` load/store | `mem_stage.sv`: data-bus master (valid/ready), byte lanes, 1-wait-state slave in TB; MEM busy freezes EX/ID/IF (`hold`); on squash a wrong-path store's transaction is suppressed while speculative loads pass through |
| Writeback | `reg_*` write | `writeback.sv`: WB mux (ALU/MEM/PC+4/CSR) → regfile write-first port; `csr.sv` cycle/instret counters tick once per retired instruction; the mispredicting branch retires here, at which point the scoreboard fires the squash |

Control decisions (Phase 3, on top of Phase 2's hazard rules):

- Branch prediction: 2-bit saturating BHT (256 entries, PC[9:2], weakly
  not-taken reset) + direct-mapped tagged BTB (64 entries, cond flag).
  Fetch continues on the predicted path; prediction bits ride IF/ID → ID/EX.
- **Late-resolving branch**: condition compares in EX, but the squash is
  deferred to the branch's WB cycle by `rtl/core/scoreboard.sv` (2-entry
  record queue: EX→MEM→WB is gapless because a branch never stalls in MEM).
  Younger instructions keep executing during the window — a distance-1
  speculative load reaches MEM (cache fill) on the squash cycle itself.
- Squash recovery: `squash` pulses from the scoreboard = pipeline-wide
  flush (fetch redirect + IF/ID, ID/EX, EX/MEM, MEM/WB cleared with priority
  over `hold`); `block_commit` (asserted from EX resolve through WB squash)
  gates wrong-path `csr_fire`, `trap_valid` and BHT/BTB training.
- Wrong-path stores never commit (`d_valid` gated for stores on the squash
  cycle — the wrong-path store is always in its first MEM cycle there);
  speculative loads are deliberately *not* gated (Spectre side channel).
- 1-cycle load-use interlock; full EX/MEM/WB forwarding; registered
  1-wait-state D-side slave (Phase 2 rules unchanged).
- Magic signature: word store to `0xFFFF0000` publishes a test result
  (`tb/integration/tb_core.sv`); the TB also prints a
  `STAT branches=… mispredicts=… rate=…%` line at the end of every run.

## L1 data cache (Phase 4)

`rtl/cache/l1_dcache.sv` sits between the pipeline's mem stage and the
external data bus; `mem_stage.sv` now only shapes requests (store lane
replication, squash store-gate) and extracts load bytes from the cache
response.

- **Geometry (default):** 16 sets × 2 ways × 16-byte lines (4 words) →
  offset `addr[3:0]`, set `addr[7:4]`, tag `addr[31:8]`. `POLICY`
  selects the replacement module: `0` = exact LRU
  (`replacement_lru.sv`, per-set move-to-front stack), `1` = tree-PLRU
  (`replacement_plru.sv`, (WAYS−1)-bit heap tree per set).
- **Write policy:** write-through, no-write-allocate. Stores always
  write memory (the ISS-visible image, the TB magic signature and any
  bus observer stay coherent) and byte-merge into the line only when it
  is already present; a store miss goes straight to memory without
  allocating. Loads fill a whole line on miss.
- **FSM:** `S_IDLE → {S_RESP (hit), S_WT (store), S_FILL (miss)}`.
  A hit latches `rsp_rdata` and answers in one cycle; a fill streams
  the 4 line words from memory (1-wait-state slave: ~2 cycles/word),
  then re-serves the request from `S_IDLE` (now a hit). `rsp_ready` is
  a one-cycle completion pulse the mem stage turns into `mem_done`.
- **Speculative fill (the Phase 5 primitive):** line identity
  (base/set/tag/way) is **latched at fill start**. Once `S_FILL` is
  entered the FSM runs to completion even if `req_valid` drops — which
  is exactly what happens when the requesting load is squashed
  mid-fill (the late-resolve flush clears EX/MEM, the pipeline
  continues, the fill finishes). The squashed instruction's data return
  is discarded (MEM/WB was cleared), but the line is left **valid** —
  a timing-visible side effect of a wrong-path load. The squash-cycle
  load is always in its *first* MEM cycle (in-order age argument), so
  gating stores there never blocks an older in-flight fill.
- **Replacement updates** fire on every served hit and on fill
  completion, always with the *latched* fill set/way (the live request
  address may already belong to a different instruction after a squash).
- **Invalidate port** (`inval_valid`, `inval_addr`): drops the line
  containing the address (tag compare, all ways); applied last in the
  state update so it wins over a same-cycle valid-set. Used by the
  Phase 5 Flush+Reload probe. `tb_core` wires it to static 0 regs that
  tests can poke.

## Mitigations (Phase 7, toggleable parameters)

| Param | Mechanism |
|---|---|
| `MIT_SPEC_BARRIER` | insert speculation barrier (fence.i-style) after bounds-check branches |
| `MIT_CHECK_BEFORE_FORWARD` | privilege/bounds check completes before result forwards |
| `MIT_FILL_ON_COMMIT` | cache lines only fill when instruction retires |

## SoC / host

Phase 8: PYNQ block design wraps `soc_top` as custom IP; `host/pynq_overlay.py`
drives it and streams probe data to the Streamlit dashboard.
