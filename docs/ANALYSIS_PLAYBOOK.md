# Analysis Playbook — How to Analyse Results

This document is central to MicroTrace. A simulator that emits metrics is not research until the experiments are controlled and the results are interpreted.

## 1. Use this analysis sequence every time

1. **Question:** What precise question are you answering?
2. **Hypothesis:** What do you expect, and why?
3. **Independent variable:** What one factor will you change?
4. **Dependent variables:** What will you measure?
5. **Controls:** What must remain fixed?
6. **Workload:** Which trace/program is used, and why?
7. **Procedure:** Exact command/configuration and number of repetitions.
8. **Validation:** How do you know the simulator is correct?
9. **Analysis:** Which statistics and charts answer the question?
10. **Interpretation:** What does the result mean?
11. **Limitations:** What cannot be concluded?
12. **Reproducibility:** Can another person rerun it?

## 2. Experiment design rules

- Change one independent variable at a time for a clean first experiment.
- For interactions, use a factorial design after one-variable experiments.
- Use the exact same workload and trace for compared configurations.
- Keep random seeds fixed for paired comparisons; also test multiple seeds if randomness matters.
- Record simulator commit/hash and configuration.
- Do not discard an inconvenient run without documenting why.
- Do not select only the best-looking result.
- Run enough repetitions to characterise variability. Deterministic traces may not need repeated identical runs; stochastic models do.
- Separate model validation from performance evaluation.

## 3. Core metric definitions

### Cache
- Accesses = hits + misses.
- Hit rate = hits / accesses.
- Miss rate = misses / accesses.
- Writeback count = number of dirty evictions written to the next level.
- AMAT = use the formula matching the hierarchy and latency definitions in the model.

### Branch prediction
- Accuracy = correct / total predictions.
- Misprediction rate = incorrect / total predictions.
- MPKI = mispredictions / committed instructions × 1,000.
- Predictor storage = number of entries × bits per entry, plus history/target structures where applicable.

### Pipeline
- CPI = total elapsed cycles / committed instructions.
- IPC = committed instructions / total elapsed cycles.
- Squash ratio = squashed instructions / fetched instructions, if event definitions make this meaningful.
- Branch penalty cycles = measured cycles attributable to branch recovery under a stated accounting rule.

### Spectre model
- Recovery accuracy = correctly recovered synthetic secret symbols / total attempted symbols.
- Leakage distinguishability: report timing distributions or a defined classifier's accuracy, with baseline and sample counts.
- False-positive rate and false-negative rate should be reported if classifying cache hits/misses.
- Do not call an arbitrary weighted number a universal “security score.” If you create a composite score, publish its formula, normalisation and limitations.

### Mitigation
- Performance overhead (%) = (mitigated runtime − baseline runtime) / baseline runtime × 100.
- Leakage reduction (%) = (baseline leakage metric − mitigated leakage metric) / baseline leakage metric × 100, only when the metric has a meaningful zero and higher-is-more-leakage interpretation.
- If leakage is a probability/accuracy near chance, report absolute changes and confidence intervals too.

## 4. Recommended experiment matrix

| ID | Question | Independent variable | Dependent metrics | Suggested chart |
|---|---|---|---|---|
| C1 | How does associativity affect misses? | Ways | Miss rate, AMAT | Line chart |
| C2 | Which replacement policy performs best? | FIFO/LRU/PLRU | Miss rate, writebacks | Grouped bars |
| C3 | How does block size affect locality? | Block size | Miss rate, traffic | Line chart |
| C4 | How do write policies affect traffic? | Write policy | Writebacks, memory writes | Stacked bars |
| B1 | Which predictor fits each branch pattern? | Predictor type | Accuracy, MPKI | Grouped bars |
| B2 | How does GShare history length matter? | History bits | Accuracy, storage | Line chart |
| B3 | Does table size reduce aliasing? | PHT entries | Accuracy | Line chart |
| P1 | How does resolution stage affect branch cost? | Resolution stage | CPI, recovery cycles | Line/bar |
| P2 | How does speculation window affect work? | Window size | Squashed instructions, cycles | Line chart |
| S1 | Can the model reveal a synthetic secret? | Training/configuration | Recovery accuracy | Line + distribution |
| S2 | What affects leakage distinguishability? | Cache/timing parameters | Classifier accuracy, overlap | Histograms/box plots |
| M1 | What does each mitigation block? | Mitigation | Leakage metric | Grouped bars |
| M2 | What is the security/performance trade-off? | Mitigation/configuration | Leakage, overhead | Pareto scatter |

## 5. How to interpret each result

For every graph, write five short statements:

1. **Observation:** What visibly changed? Include actual values.
2. **Mechanism:** Which architectural mechanism explains the change?
3. **Magnitude:** Is the difference large or small? Give absolute and relative change.
4. **Caveat:** What other explanation or model limitation exists?
5. **Conclusion:** What can you responsibly claim?

Bad interpretation:
“LRU is better than FIFO.”

Good interpretation:
“On trace T under a 16 KiB, 4-way cache with 64-byte lines, LRU reduced the miss rate from X to Y relative to FIFO. The trace repeatedly revisits a working set whose recency information is useful to LRU. This does not establish that LRU is universally superior; the result is workload- and configuration-dependent.”

## 6. Statistical treatment

For repeated measurements:
- Report sample count `n`.
- Report mean and standard deviation, or median and interquartile range for skewed distributions.
- Plot individual points where practical.
- Use confidence intervals when comparing noisy measurements.
- For paired runs, analyse paired differences rather than treating runs as unrelated.
- Do not claim statistical significance solely because two means differ.

For deterministic simulator runs:
- Repetition may produce identical values and add no information.
- Instead, test multiple workloads, input traces and parameter combinations.
- Use randomized seeds only when the model contains stochastic behaviour.

## 7. Correlation and sensitivity

Correlation:
- Build a matrix only for variables with a meaningful relationship and sufficient observations.
- Use Pearson for approximately linear relationships; Spearman for monotonic rank relationships or non-normal distributions.
- Correlation is descriptive, not causal.
- Avoid mixing measurements from unrelated workloads without stratification.

Sensitivity:
- Sweep one parameter across a defined range.
- Plot output metrics against the parameter.
- Calculate local/relative sensitivity where useful.
- Identify thresholds, plateaus and reversals.
- For interactions, use a grid/heatmap or factorial experiment.

## 8. Performance-security Pareto analysis

Plot:
- X-axis: performance overhead (%), lower is better.
- Y-axis: leakage metric, lower is better.
- One point per configuration/mitigation.
- Label points and show baseline.

A point is Pareto-dominated if another point is no worse on both metrics and strictly better on at least one. The Pareto frontier shows the non-dominated trade-offs. It does not identify a universally best mitigation; the threat model and acceptable overhead determine the choice.

## 9. Data and chart quality checklist

- [ ] Every result has an experiment ID.
- [ ] Axes include units.
- [ ] Sample size is stated.
- [ ] Baseline is identified.
- [ ] Configuration is visible or linked.
- [ ] Raw data is retained.
- [ ] No unexplained axis truncation.
- [ ] No 3D chart where a 2D chart communicates better.
- [ ] Colour is not the only way to distinguish series.
- [ ] Plot can be regenerated by script.
- [ ] Chart caption states the main finding, not just the chart type.

## 10. Final results table

For each major research question, provide:
- Hypothesis.
- Experiment IDs.
- Configuration range.
- Workload.
- Primary metric.
- Result with uncertainty.
- Interpretation.
- Limitation.
- Conclusion.
