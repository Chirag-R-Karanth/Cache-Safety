# How to use this repository

This repository is the **MicroTrace project starter kit**. It contains the learning plan, architecture and analysis specifications, experiment templates, and starter data files. It does not contain a working simulator yet.

## Start here

1. Read [README.md](README.md) for scope and engineering rules.
2. Read [docs/WHAT_TO_UNDERSTAND.md](docs/WHAT_TO_UNDERSTAND.md) in order. Work through the hand calculations; do not skip them.
3. Follow [docs/ROADMAP.md](docs/ROADMAP.md) week by week. Each week has deliverables and exit criteria.
4. Track implementation work in [templates/TODO.md](templates/TODO.md). Mark a task complete only when its deliverable exists and its acceptance check passes.
5. Before running an experiment, copy [templates/EXPERIMENT_PLAN.md](templates/EXPERIMENT_PLAN.md), fill it in, and register the experiment in [data/experiment_register.csv](data/experiment_register.csv).
6. Use [docs/ANALYSIS_PLAYBOOK.md](docs/ANALYSIS_PLAYBOOK.md) to validate, analyse, and interpret results.
7. Use [templates/RESULTS_SCHEMA.md](templates/RESULTS_SCHEMA.md) as the run-data contract. Copy [data/results_template.csv](data/results_template.csv) to a separate results file (for example, `data/results.csv`) and append one record per completed run. Keep the template itself unchanged. Preserve raw metrics, configuration files and event traces separately.
8. Use [prompts/AI_PROMPTS.md](prompts/AI_PROMPTS.md) as tutoring and review prompts. Supply actual source/data to the assistant; reject invented metrics or results.

## Repository map

- `docs/`: roadmap, concepts, architecture, analysis, visualisation, and report guidance.
- `templates/`: task, experiment, result-schema, and decision-log templates.
- `data/experiment_register.csv`: planned/active/completed experiment index.
- `data/results_template.csv`: header-only one-row-per-run CSV template; copy it before recording results.
- `prompts/AI_PROMPTS.md`: prompts for learning, code review, experiment design, and report review.

## Important

- The starter CSV contains column names only; it is not measured data.
- Do not overwrite previous run outputs. Give each run an immutable experiment/configuration/trial identity.
- Keep failed and invalid runs with their status and logs; do not silently discard them.
- Do not start the Spectre demonstration before the cache, predictor, pipeline, and speculative-state models have been validated.
- The Spectre work is restricted to the synthetic model described in the README and roadmap.
