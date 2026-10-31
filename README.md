# MicroTrace — Project Starter Kit

**Project:** Interactive Microarchitectural Performance and Security Analysis Platform  
**Scope:** Cache hierarchy and controller, branch prediction, pipelining, speculative execution, Spectre V1 (synthetic model), mitigations, experimental analysis and visualisation.

> **Project status:** planning/scaffolding. This repository currently contains specifications, templates and starter experiment data. It is not yet an executable simulator.

## Start here

Follow [howto.md](howto.md) for the onboarding sequence. The main project plan is [docs/ROADMAP.md](docs/ROADMAP.md).

## What this kit contains

- `docs/ROADMAP.md` — week-by-week implementation plan and exit criteria.
- `docs/WHAT_TO_UNDERSTAND.md` — concepts to learn, in dependency order.
- `docs/ANALYSIS_PLAYBOOK.md` — how to design, run, analyse and explain experiments.
- `docs/ARCHITECTURE_SPEC.md` — recommended system boundaries and data flow.
- `docs/VISUALISATION_SPEC.md` — dashboard pages, charts and interaction requirements.
- `docs/REPORT_OUTLINE.md` — final report structure and what each section must prove.
- `templates/TODO.md` — task checklist.
- `templates/EXPERIMENT_PLAN.md` — reusable experiment planning sheet.
- `templates/RESULTS_SCHEMA.md` — required fields for reproducible results.
- `templates/DECISION_LOG.md` — record important design decisions.
- `prompts/AI_PROMPTS.md` — prompts for using an AI assistant without outsourcing understanding.
- `data/experiment_register.csv` — experiment register starter.
- `data/results_template.csv` — long-format results template.

## Non-negotiable engineering rules

1. Build a correct software reference model before RTL.
2. Keep simulation, experiment orchestration, analysis and visualisation separate.
3. Every plotted result must be generated from saved raw data.
4. Every experiment must record its configuration, workload, seed, software version and metric definitions.
5. Never compare two configurations while silently changing multiple variables.
6. Validate each model against hand-worked cases or an independent reference.
7. Treat Spectre as a controlled synthetic demonstration. Do not target real machines, processes or secrets.
8. Clearly label model assumptions. A simplified simulator does not establish real-CPU security guarantees.
9. Preserve every completed run and its metadata. Never reuse an output path for a different run.

## Recommended first action

Read [docs/WHAT_TO_UNDERSTAND.md](docs/WHAT_TO_UNDERSTAND.md), then complete Week 1 in [docs/ROADMAP.md](docs/ROADMAP.md). Do not start implementing Spectre first.


## Parameter sweep

Compare 1-, 2- and 4-way caches under both LRU and FIFO using the identical trace:

```bash
python3 scripts/run_sweep.py --binary ./cache_sim --trace traces/locality_demo.trace --out-dir results/sweep --capacity 256 --line-size 64
```

This writes per-configuration raw CSVs, `comparison.csv`, and `hit-rate-comparison.svg`.
