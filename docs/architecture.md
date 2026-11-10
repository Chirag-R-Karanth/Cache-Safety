# Architecture

> Status: **Phase 0 baseline.** Pipeline/cache diagrams are completed in
> Phase 2+; see [build reports](build-reports/) for incremental updates.

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

_Filled in during Phase 2:_

| Pipeline stage | PicoRV32 FSM state(s) | Notes |
|---|---|---|
| Fetch | `mem_state` fetch / `reg_prefetched` | becomes predicted-PC fetch in Phase 3 |
| Decode | decoder `case (instr)` | reused nearly as-is |
| Execute | `alu_*`, `pcpi` | + branch resolve in Phase 3 |
| Memory | `mem_state` load/store | + L1 dcache in Phase 4 |
| Writeback | `reg_*` write | + scoreboard release |

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
