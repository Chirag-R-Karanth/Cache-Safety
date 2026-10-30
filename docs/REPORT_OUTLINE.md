# Final Report Outline

## Title
MicroTrace: An Interactive Platform for Microarchitectural Performance and Security Analysis

## Abstract
State the problem, modelled architecture, methods, major measured findings and limitations. Do not claim results before experiments are complete.

## 1. Introduction
- Why caches and branch prediction exist.
- Why speculative execution matters.
- How performance optimisations create security implications.
- Project objectives and contributions.

## 2. Background
- Cache hierarchy and controller.
- Branch prediction.
- Pipeline and speculation.
- Cache side channels.
- Spectre Variant 1.
- Mitigation families.

## 3. Related Work
Summarise primary research and tools. Cite original papers and official technical documentation. Distinguish prior work from your implementation.

## 4. System Design
- Requirements.
- Architecture diagram.
- Module boundaries.
- Data flow.
- Configuration model.
- Event logging and reproducibility.

## 5. Implementation
- Cache model and RTL controller.
- Replacement and write policies.
- Branch predictor implementations.
- Five-stage pipeline.
- Speculative execution model.
- Synthetic Spectre V1 demonstration.
- Mitigations.
- Dashboard.

## 6. Experimental Methodology
For every experiment:
- Research question and hypothesis.
- Independent/dependent/control variables.
- Workload.
- Parameter values.
- Number of trials and seeds.
- Metrics and formulas.
- Validation procedure.
- Hardware/software environment, if relevant.

## 7. Results
Organise by research question, not by source-code module.
- Cache results.
- Predictor results.
- Pipeline results.
- Spectre leakage results.
- Mitigation results.
- Performance-security trade-offs.

Every figure must have a caption, units, sample count where relevant, and interpretation.

## 8. Discussion
- Explain mechanisms behind results.
- Compare results with expectations and literature.
- Discuss surprising results.
- Explain workload dependence.
- Explain performance/security trade-offs.

## 9. Limitations and Threats to Validity
- Abstraction versus real hardware.
- Simplified timing.
- Missing out-of-order features, if applicable.
- No real CPU exploit validation.
- Workload representativeness.
- Measurement noise and statistical limits.

## 10. Conclusion and Future Work
Summarise what was demonstrated, what was measured and what remains unmodelled.

## Appendices
- Configuration schema.
- Test cases.
- Experiment register.
- Additional plots.
- Build and reproduction commands.
- Glossary.
