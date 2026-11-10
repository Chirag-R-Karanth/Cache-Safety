# PicoRV32 fork

- **Upstream:** https://github.com/YosysHQ/picorv32
- **Upstream commit:** `ef203c2b0a3fb793280f5114941416c425c5b461` (2026-09-07)
- **License:** permissive (see `COPYING`)
- **Vendored files:** `picorv32.v` (core + helpers), `testbench_ez.v`
  (reference smoke testbench with inline program), `UPSTREAM_README.md`.

## Why this fork

The project spec allows forking SERV or PicoRV32 as the starting RV32I core
instead of writing the base ISA implementation from scratch. PicoRV32 was
chosen because:

1. Single-file, plain-Verilog core that simulates cleanly under Icarus.
2. Its instruction decoder, ALU, CSR logic and register file are directly
   reusable when we evolve the core into a pipelined, speculative design.
3. Large upstream test suite and active maintenance.

## Planned modifications (see `docs/architecture.md`)

- Map the multi-cycle FSM onto fetch/decode/execute/mem/writeback stages.
- Add 2-bit BHT + BTB branch prediction with predict-and-continue fetch.
- Add a scoreboard so younger instructions issue while a branch is unresolved;
  squash/recover on misprediction.
- Attach a set-associative L1 data cache to the memory interface.
- Add user/supervisor privilege mode + delayed privilege check (Meltdown demo).

Upstream files are kept unmodified in this directory as a reference baseline;
our modified pipeline lives alongside in `rtl/core/`.
