# Cache-Safety — Hardware Spectre/Meltdown Demonstration on FPGA

Cycle-accurate cache simulator + speculative RV32I core (SystemVerilog) that
demonstrates **Spectre v1** and a **Meltdown-style** transient-execution
attack with toggleable hardware mitigations, visualized on a real-time
dashboard. Target: PYNQ-Z1/Z2 (Zynq-7000).

> Educational project. See [docs/threat-model.md](docs/threat-model.md) for
> exactly what is and is not demonstrated. Do not target real machines or
> real secrets.

## Repository layout

```
sim/         Software cache simulator (design exploration, sweeps, AMAT)
rtl/         SystemVerilog: core (PicoRV32 fork), predictor, cache, mitigations, SoC top
attacks/     Spectre v1 + Meltdown victim/attacker source
tb/          Testbenches: unit, integration, attack
fpga/        PYNQ constraints, Vivado block design, build scripts
host/        PYNQ overlay control + Streamlit/Plotly dashboard
scripts/     Run/lint/build helper scripts
docs/        Architecture, threat model, results, build reports, spec
```

## Quick start

### Software cache simulator

```bash
make sim build cache_sim from sim/src/cache.cpp
make test-sim        # unit tests (Python unittest/pytest-compatible)
./cache_sim --trace sim/traces/locality_demo.trace --out /tmp/run \
    --capacity 256 --line-size 64 --ways 2 --policy lru
python3 scripts/run_sweep.py --binary ./cache_sim   # design-space sweep + chart
```

### RTL smoke test (Icarus Verilog)

```bash
make test-rtl        # compiles forked PicoRV32 + self-checking testbench
make waves           # same + VCD dump for GTKWave
```

### Full test suite

```bash
make test            # cache sim + RTL smoke
```

## Toolchain

| Tool | Use |
|---|---|
| g++ (C++17) | cache simulator |
| Python 3.10+ | tests, sweeps, dashboard (`pip install -r requirements.txt`) |
| Icarus Verilog 11+ / GTKWave | RTL simulation & debug |
| Verilator | CI lint (GitHub Actions) |
| RISC-V GNU toolchain | compiling victim/attacker C (Phase 5+) |
| Xilinx Vivado | PYNQ bitstream (Phase 8) |
| PYNQ Python API | host-side overlay control |

## Documentation

- [Project specification](docs/SPEC.md) — full master prompt / plan
- [Threat model](docs/threat-model.md)
- [Architecture](docs/architecture.md) — pipeline, cache org, diagrams
- [Results](docs/results.md) — analytics & interpretation
- [Build reports](docs/build-reports/) — per-phase status, tests, PR links

## Workflow

`main` (always green) ← `develop` ← feature branches. One PR per phase,
squash-merged after tests pass; phase tags `v0.1-cache-sim` … `v1.0-final`.

## License

MIT — see [LICENSE](LICENSE). PicoRV32 fork retains its own license
([rtl/core/picorv32/COPYING](rtl/core/picorv32/COPYING)).
