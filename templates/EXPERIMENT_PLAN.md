# Experiment Plan

## Identification
- Experiment ID (stable and unique):
- Date/time (UTC):
- Git commit:
- Simulator version:
- Research question:

## Hypothesis
What do you expect, and what architectural mechanism supports the expectation?

## Variables and controls
- Independent variable (change one for a controlled comparison):
- Dependent variable(s):
- Controlled variables:
- Workload ID:
- Workload file and SHA-256:
- Baseline configuration ID:
- Treatment configuration ID(s):

## Procedure
1.
2.
3.

## Repetitions and randomness
- Number of trials:
- Random seeds (one per trial, or explicitly deterministic):
- Are runs paired or independent?
- Why is this trial policy appropriate?

## Metric definitions
| Metric | Exact definition/formula | Unit | Direction (better/worse) |
|---|---|---|---|
| | | | |

State denominator and missing/not-applicable handling. Do not mix fractions and percentages.

## Validation before analysis
- Hand calculation or independent reference:
- Directed test cases:
- Expected invariants:
- Conditions that make a run invalid:

## Run artefacts
- Immutable configuration file(s):
- Raw metrics path(s):
- Event trace path(s):
- stdout/stderr or run log:
- Analysis script and version:
- Figure paths:

## Results
| Configuration | Trial | Status | Primary metric(s) | Notes |
|---|---:|---|---|---|
| | | | | |

## Interpretation
1. **Observation:** include actual values and sample count.
2. **Mechanism:** explain the architectural cause.
3. **Magnitude:** report absolute and relative changes.
4. **Uncertainty:** report variation or explain why no repeated trials are needed.
5. **Caveat:** identify alternative explanations and model limitations.
6. **Conclusion:** state only what the experiment supports.

## Limitations
What does this experiment not establish?

## Reproduction
Exact command, configuration path, workload path/hash, seed(s), and expected output location:
