# Visualisation and Dashboard Specification

## Design objective

The dashboard is an investigation tool. Every chart must answer a defined question and allow a user to inspect the underlying run.

## Page 1 — Overview
- System configuration summary.
- Most recent experiment runs.
- Cache hit rate, AMAT, predictor accuracy, CPI/IPC and leakage metric.
- Baseline-versus-selected comparison.
- Links to failed/invalid runs.

## Page 2 — Architecture explorer
- CPU → cache hierarchy → memory diagram.
- Selectable component detail.
- Animated request path.
- Instruction/cycle stepper.
- Current cache and predictor state.
- Clearly distinguish architectural state from microarchitectural state.

## Page 3 — Cache laboratory
Required:
- Hit/miss time series.
- Cache-set × time heatmap.
- Replacement/eviction event list.
- AMAT comparison.
- Associativity and line-size sensitivity.
- L1/L2 traffic breakdown.
- Address trace replay.

Interactions:
- Select an access and show tag/index/offset.
- Select a set and inspect its lines.
- Step through replacement decisions.
- Compare two saved configurations.

## Page 4 — Branch predictor laboratory
Required:
- Accuracy by predictor and workload.
- Accuracy over trace position.
- Confusion matrix.
- 2-bit counter transition visualiser.
- GShare history and PHT index inspection.
- Table-size/history-length sensitivity.

Interactions:
- Step through a branch trace.
- Inspect predicted versus actual outcome.
- Inspect predictor state before and after update.

## Page 5 — Pipeline and speculation
Required:
- Cycle-by-cycle pipeline timeline.
- Stage occupancy.
- Stall/flush markers.
- Committed versus squashed instruction counts.
- CPI/IPC breakdown.
- Branch recovery timeline.

Interactions:
- Step, play, pause and reset.
- Select instruction and inspect its history.
- Filter by branch, load, stall or squash events.

## Page 6 — Security laboratory
Required:
- Synthetic Spectre V1 timeline.
- Predictor training phase.
- Transient execution phase.
- Squash/recovery phase.
- Cache footprint heatmap.
- Timing distribution.
- Recovery accuracy across trials.

Interactions:
- Toggle baseline versus mitigation.
- Adjust model parameters.
- Replay the same synthetic workload.
- Inspect why an observation is classified as a hit/miss.

## Page 7 — Research and analytics
Required:
- Experiment matrix.
- Configuration comparison.
- Parameter sweep.
- Sensitivity plots.
- Correlation matrix with sample count.
- Pareto frontier: performance overhead versus leakage.
- Export CSV and report.

## Chart-selection rules

| Question | Preferred chart |
|---|---|
| How does a metric evolve over cycles? | Line chart |
| Which of a few configurations is best? | Bar/dot plot |
| Which sets/lines are active? | Heatmap |
| What is the distribution of timing? | Histogram/box plot |
| Are two continuous metrics related? | Scatter plot |
| How do two parameters interact? | 2D heatmap |
| Which choices are non-dominated? | Pareto scatter |
| How does traffic move through hierarchy? | Sankey, if quantities are meaningful |

## Visual quality requirements
- Use consistent units and definitions.
- Show experiment ID and workload.
- Show sample count and uncertainty where applicable.
- Use accessible colours and do not rely on colour alone.
- Avoid ornamental 3D charts.
- Do not use fake or hard-coded data in the final application.
- Provide an empty state when no experiment has been run.
- Allow chart export and raw data inspection.
