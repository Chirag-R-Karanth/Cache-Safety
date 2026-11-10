# Project Specification: Hardware Cache Simulator with Spectre/Meltdown Attack & Mitigation Demonstration on FPGA

## 0. Master Prompt (use this to brief yourself, a teammate, or an AI coding assistant)

```
I am building a semester-grade project that demonstrates Spectre v1 and Meltdown-style
transient execution attacks on a custom RISC-V (RV32I) speculative core, implemented in
SystemVerilog and deployed on an FPGA, with a software-side cache simulator for design
exploration and a real-time analytics dashboard for visualization.

Deliverables:
1. A cycle-accurate cache simulator (C++ or Python) supporting configurable size,
   associativity, line size, replacement policy, and write policy, producing hit/miss,
   AMAT, and design-space sweep data.
2. An RV32I core in SystemVerilog with: a 5-stage pipeline extended with a scoreboard
   (or small out-of-order load path) so a branch can resolve AFTER younger instructions
   have issued; a 2-bit saturating counter branch predictor with BTB; a set-associative
   L1 data cache with configurable replacement; a cycle-counter CSR; and a simple
   user/supervisor privilege mode for the Meltdown demo.
3. A Spectre v1 proof-of-concept: mistrain the branch predictor, trigger speculative
   out-of-bounds access, recover a secret byte via Flush+Reload on the cache.
4. A Meltdown-style proof-of-concept: exploit delayed privilege-check-vs-use ordering
   on a faulting/protected load to leak kernel-only data into cache state before the
   fault is handled.
5. Hardware mitigations implemented as toggleable RTL parameters: speculation barrier
   (fence), check-before-forward ordering fix, cache-fill-on-commit (invisible
   speculation). Each must be benchmarkable for IPC/cycle cost vs leak success rate.
6. Verification: Verilator/Icarus testbench, VCD waveforms, directed + randomized tests,
   CI via GitHub Actions running the testbench on every push.
7. A real-time analytics dashboard (Python, Plotly/Streamlit) fed by UART from the FPGA
   showing: per-byte probe latency curves, cache heatmaps, leak accuracy vs trials,
   mitigation comparison charts, and annotated pipeline/speculation-window waveforms.
8. Full git history with meaningful commits, branch-per-feature workflow, and a
   polished README with architecture diagrams, build/run instructions, and results.

Target board: PYNQ (PYNQ-Z1/Z2 class board, Zynq SoC)
Toolchain: Icarus Verilog + GTKWave for simulation/debug; Xilinx Vivado for bitstream
generation and the PYNQ block design; RISC-V GNU toolchain for compiling victim/attacker
C code; PYNQ Python overlay API for host-side control instead of a separate UART bridge.
Timeline: 10 weeks
Team size: 3 (one person — me — driving RTL/core/attacks end-to-end; teammates assigned
to the software cache simulator and the analytics dashboard in parallel, see team
allocation section)
Base core: forking allowed — fork SERV or PicoRV32 as the starting RV32I core, then
modify it directly to add the scoreboard / late-resolving-branch behavior needed for
speculation. Do not build the base ISA pipeline from scratch.

Build the project in the phase order given in the implementation plan below, committing
working, tested increments at each phase boundary. Do not attempt full out-of-order
execution — use a scoreboard-based "speculative load, late-resolving branch" design,
which is the minimum needed for Spectre v1 and is tractable in one semester.
```

---

## 1. Repository Structure

```
cache-spectre-meltdown-fpga/
├── README.md
├── LICENSE
├── .gitignore
├── .github/
│   └── workflows/
│       └── ci.yml                 # Verilator build + test on every push
├── docs/
│   ├── architecture.md            # Block diagrams, pipeline stages, cache org
│   ├── threat-model.md            # What exactly is being demonstrated & why
│   ├── results.md                 # Final analytics, screenshots, writeup
│   └── diagrams/                  # .drawio / exported .png / .svg
├── sim/                           # Software cache simulator (design exploration)
│   ├── src/
│   │   ├── cache.cpp / cache.py
│   │   ├── replacement_policies.cpp
│   │   └── trace_runner.cpp
│   ├── traces/                    # Memory access traces (synthetic + benchmark)
│   ├── tests/
│   │   └── test_cache.cpp         # pytest or GoogleTest
│   └── results/                   # CSV/JSON outputs of sweeps
├── rtl/                           # SystemVerilog hardware
│   ├── core/
│   │   ├── fetch.sv
│   │   ├── decode.sv
│   │   ├── scoreboard.sv
│   │   ├── execute.sv
│   │   ├── mem_stage.sv
│   │   ├── writeback.sv
│   │   └── csr.sv
│   ├── predictor/
│   │   ├── bht_2bit.sv
│   │   ├── btb.sv
│   │   └── gshare.sv              # optional upgrade
│   ├── cache/
│   │   ├── l1_dcache.sv
│   │   ├── replacement_lru.sv
│   │   └── replacement_plru.sv
│   ├── mitigations/
│   │   ├── speculation_barrier.sv
│   │   ├── check_before_forward.sv
│   │   └── cache_fill_on_commit.sv
│   └── top/
│       └── soc_top.sv             # Core + cache + UART + CSR glue
├── attacks/
│   ├── spectre_v1/
│   │   ├── victim.S / victim.c
│   │   ├── attacker.c
│   │   └── flush_reload.c
│   └── meltdown/
│       ├── victim_priv.c
│       └── attacker.c
├── tb/                            # Testbenches
│   ├── unit/
│   │   ├── tb_bht.sv
│   │   ├── tb_btb.sv
│   │   └── tb_dcache.sv
│   ├── integration/
│   │   └── tb_core_top.sv
│   └── attack/
│       ├── tb_spectre_v1.sv
│       └── tb_meltdown.sv
├── fpga/
│   ├── constraints/
│   │   └── pynq_z1.xdc            # or pynq_z2.xdc
│   ├── block_design/
│   │   └── soc_bd.tcl             # Vivado block design: PS + PL core/cache as custom IP
│   ├── build.tcl                  # Vivado non-project-mode build script
│   └── bitstreams/                # .bit + .hwh (gitignored, or Git LFS)
├── host/
│   ├── pynq_overlay.py            # PYNQ overlay load + PS<->PL register/AXI control
│   ├── uart_bridge.py             # Optional fallback if not using PYNQ overlay path
│   └── dashboard/
│       ├── app.py                 # Streamlit/Plotly dashboard, fed by pynq_overlay.py
│       └── assets/
├── scripts/
│   ├── run_sim.sh
│   ├── run_lint.sh                 # Verilator --lint-only, or Verible
│   └── program_fpga.sh
└── requirements.txt / Makefile
```

---

## 2. Git & Workflow Plan

- **Branching:** `main` (always builds + passes tests) ← `develop` ← feature branches (`feat/bht-predictor`, `feat/l1-dcache`, `feat/spectre-poc`, `fix/...`).
- **Commit discipline:** one logical change per commit, imperative subject line (`Add 2-bit BHT with configurable table size`), body explains *why* when non-obvious. No "wip" or "fix stuff" commits on `main`.
- **Tags:** tag each phase completion — `v0.1-cache-sim`, `v0.2-core-pipeline`, `v0.3-predictor`, `v0.4-spectre-poc`, `v0.5-meltdown-poc`, `v0.6-mitigations`, `v1.0-final`.
- **PRs even solo:** open a PR per feature branch into `develop`, use it as a self-review checkpoint and a changelog; squash-merge.
- **CI (`.github/workflows/ci.yml`):** on push/PR — lint RTL (Verible or Verilator `--lint-only`), build and run unit testbenches (Verilator), run the Python cache simulator's test suite, fail the build on any test failure or lint error.
- **Issues:** file one issue per planned module from the implementation plan below; close via commit messages (`Closes #4`).

---

## 3. Team Allocation (3 people, you driving RTL/core/attacks)

| Person | Owns | Runs in parallel from |
|---|---|---|
| You | Core RTL (fork + scoreboard mods), predictor, cache RTL, both attack PoCs, mitigations | Phases 2–7 |
| Teammate A | Software cache simulator (Phase 1), replacement policy sweeps, trace generation | Week 1, independent of RTL |
| Teammate B | PYNQ overlay integration + Streamlit/Plotly dashboard (Phase 8 groundwork) | Week 1 — can build against mocked/simulated data until real hardware output exists in Phase 5–6 |

Keep A and B's work decoupled from your RTL by having them consume **CSV/JSON output
files** (from the software simulator and from Icarus testbench dumps) rather than
needing the live board — this lets them finish most of their work before your hardware
is ready, and avoids you becoming a bottleneck for their grade.

## 4. Testing Strategy

| Layer | Tool | What's tested |
|---|---|---|
| Cache simulator | GoogleTest / pytest | Hit/miss correctness per policy, edge cases (cold cache, full associativity, single-line cache) |
| BHT/BTB | Verilator + SV testbench | Saturating counter transitions, aliasing behavior, BTB hit/miss |
| L1 D-cache RTL | Verilator + SV testbench | Read/write hit/miss, write-back vs write-through, replacement correctness, coherence with mem stage |
| Core pipeline | Verilator + directed assembly tests | Hazard handling, correct squash on misprediction, scoreboard stalls |
| Spectre PoC | Integration testbench + host script | Secret byte recovery rate across N trials, probe-latency histogram sanity |
| Meltdown PoC | Integration testbench | Leak rate with/without privilege-check-before-use mitigation |
| Mitigations | Regression suite | Confirm leak success drops to near-zero; confirm IPC/cycle delta measured and logged |
| Full SoC on FPGA | On-hardware smoke test via UART | Boot, run known program, verify checksum/output against simulation |

Use **randomized instruction sequence testing** (constrained-random, even a simple Python generator feeding assembly) in addition to directed tests to catch pipeline hazard bugs the directed tests miss — this is worth highlighting to a grader as rigor.

---

## 5. Step-by-Step Implementation Plan

**Phase 0 — Setup (Week 1)**
- Repo scaffold above, CI skeleton, toolchain installed and verified (Icarus "hello world" sim, PYNQ board boots and runs a stock overlay to confirm the board/image itself works).
- Fork SERV or PicoRV32 into `rtl/core/`, get it simulating standalone in Icarus before any modification.
- Write `docs/threat-model.md`: precisely state what you will and won't demonstrate, and why a toy core is necessary and sufficient.
- Kick off Teammate A (cache simulator) and Teammate B (dashboard scaffold) in parallel this same week.

**Phase 1 — Software Cache Simulator (Weeks 1–2)**
- Implement configurable cache model + replacement policies.
- Run sweeps across size/associativity/line size on at least 2 real memory traces.
- Produce first analytics: hit-rate curves, AMAT plots. This de-risks the project early and gives you a grade-safe fallback deliverable.

**Phase 2 — Baseline RV32I Pipeline (Weeks 2–4, shortened by the fork)**
- Get the forked SERV/PicoRV32 core running your own directed tests and a small compiled C program (via riscv-gnu-toolchain) in Icarus, so you fully understand its pipeline before modifying it.
- Document, in `docs/architecture.md`, exactly where the fork's stages map to fetch/decode/execute/mem/writeback — you'll need this map for Phase 3's scoreboard insertion.

**Phase 3 — Branch Predictor + Speculation (Weeks 4–5)**
- Add 2-bit BHT + BTB, predict-and-continue fetch.
- Add scoreboard so younger instructions can execute while a predicted branch is unresolved; add squash/recovery on misprediction.
- Test: misprediction rate on a branchy benchmark; confirm squash correctness with randomized tests.

**Phase 4 — L1 Data Cache (Weeks 5–6)**
- Integrate set-associative cache into mem stage.
- Confirm timing-visible side effects (a load changes cache state even if later squashed) — this is the property the attack depends on, verify it explicitly with a testbench.

**Phase 5 — Spectre v1 PoC (Weeks 6–7)**
- Write victim code with bounds check + secret array, attacker code with mistraining loop + Flush+Reload probe.
- Run in simulation first (fast iteration), then on FPGA via UART-controlled timing probe.
- Produce the signature plot: probe latency vs byte value, 256 points, one clear dip.

**Phase 6 — Meltdown PoC (Weeks 7–8)**
- Add minimal privilege mode + protected memory region.
- Exploit ordering where the load executes before the fault/permission check completes.
- Measure leak success rate.
- Get first real board runs via the PYNQ overlay this phase, not later — both attacks should be producing live hardware data by end of Phase 6 so Teammate B's dashboard has real input before Phase 8.

**Phase 7 — Mitigations (Weeks 8–9)**
- Implement each mitigation as a parameterized toggle.
- Re-run both attacks with each mitigation on, log leak success rate and IPC/cycle overhead.
- This comparison table/chart is your strongest analytical result — budget real time for it.

**Phase 8 — Dashboard + Polish (Weeks 9–10)**
- Finish wiring the PYNQ overlay (`host/pynq_overlay.py`) into the Streamlit/Plotly dashboard for live probe data.
- Record a clean demo run (video backup in case live FPGA demo misbehaves during grading).
- Finalize README with architecture diagram, how-to-run, and results summary.
- Write `docs/results.md` consolidating every chart with 2–3 sentence interpretation each.

---

## 6. Remaining open question

Whether to target PYNQ-Z1 or PYNQ-Z2 specifically changes only the `.xdc` constraints
file and pin mapping — confirm which board revision you actually have before Phase 7's
bitstream build so `fpga/constraints/` is correct the first time.
