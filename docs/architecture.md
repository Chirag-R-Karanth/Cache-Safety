# Architecture

> Status: **Phase 2 — baseline 5-stage pipeline complete.** Phase 3 adds the
> BHT/BTB predictor on top of this structure; see [build reports](build-reports/)
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
| Fetch | `mem_state` fetch / `reg_prefetched` | `rtl/core/fetch.sv`: predicted-PC fetch, valid/ready issue handshake, skid register for 1-wait-state responses; redirect/flush on EX taken branch |
| Decode | decoder `case (instr)` | `decode_comb.sv` (pure decode) + `decode.sv` (ID/EX register, regfile read, flush/hold/load-use-bubble control); forwarding operands captured at ID/EX |
| Execute | `alu_*`, `pcpi` | `execute.sv`: full EX/MEM→EX and MEM/WB→EX forwarding, ALU, branch/jump resolve in EX with flush of younger stages, CSR request |
| Memory | `mem_state` load/store | `mem_stage.sv`: data-bus master (valid/ready), byte lanes, 1-wait-state slave in TB; MEM busy freezes EX/ID/IF (`hold`) |
| Writeback | `reg_*` write | `writeback.sv`: WB mux (ALU/MEM/PC+4/CSR) → regfile write-first port; `csr.sv` cycle/instret counters tick once per retired instruction |

Baseline control decisions (Phase 2):

- Branch prediction: predict-not-taken; resolve in EX, redirect + flush of
  fetch/decode/EX-younger stages (Phase 3 replaces this with BHT/BTB).
- 1-cycle load-use interlock (`load_use` holds IF/ID until the load leaves EX);
  `mem_busy` additionally blocks ID advance so a consumer never enters EX while
  its producer-load is still in MEM.
- Data memory: registered 1-wait-state slave (picorv32-style); during `hold`
  the WB slot keeps its content so WB→EX forwarding into the frozen EX stage
  still works (regfile re-write is idempotent; `csr.retire` is gated to the
  first cycle of each WB residency).
- Magic signature: word store to `0xFFFF0000` publishes a test result
  (`tb/integration/tb_core.sv`), the same convention `tests/start.S` uses.

## Branch prediction (Phase 3)

- 2-bit saturating-counter BHT, indexed by PC bits; BTB for target.
- Predict-and-continue fetch; branch resolves in Execute; mispredict →
  squash younger in-flight instructions and refetch correct path.

## L1 data cache (Phase 4)

- Set-associative, configurable ways/line size/replacement (LRU/PLRU).
- Fills occur at speculatively-issued load time (by design — this is the
  property Spectre exfiltrates); mitigation `FILL_ON_COMMIT` moves fills to
  commit point.

## Mitigations (Phase 7, toggleable parameters)

| Param | Mechanism |
|---|---|
| `MIT_SPEC_BARRIER` | insert speculation barrier (fence.i-style) after bounds-check branches |
| `MIT_CHECK_BEFORE_FORWARD` | privilege/bounds check completes before result forwards |
| `MIT_FILL_ON_COMMIT` | cache lines only fill when instruction retires |

## SoC / host

Phase 8: PYNQ block design wraps `soc_top` as custom IP; `host/pynq_overlay.py`
drives it and streams probe data to the Streamlit dashboard.
