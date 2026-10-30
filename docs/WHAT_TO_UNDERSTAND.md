# What You Must Understand

Use this as a learning syllabus. Do not merely read definitions; solve problems, draw state diagrams and explain each concept without notes.

## 1. Cache fundamentals

### Must know
- Locality: temporal and spatial.
- Cache line/block, tag, index, offset.
- Capacity, line size, associativity and number of sets.
- Valid and dirty bits.
- Direct-mapped, set-associative and fully associative mapping.
- Compulsory, capacity and conflict misses.
- Read hit, read miss, write hit and write miss.
- Write-through versus write-back.
- Write-allocate versus no-write-allocate.
- FIFO, LRU and pseudo-LRU.
- Inclusive, exclusive and non-inclusive hierarchy concepts.
- AMAT and memory-stall cost.

### Formulas
Let:
- `C` = cache data capacity in bytes.
- `B` = cache block size in bytes.
- `A` = associativity (ways).

Then:
- Number of cache lines = `C / B`.
- Number of sets = `C / (B × A)`.
- Offset bits = `log2(B)` when B is a power of two.
- Index bits = `log2(number of sets)` when the number of sets is a power of two.
- Tag bits = address bits − index bits − offset bits.
- Hit rate = hits / total accesses.
- Miss rate = misses / total accesses.
- AMAT (single-level simplified model) = hit time + miss rate × miss penalty.

For a two-level hierarchy, define exactly what the L1 miss penalty means. One common form is:
`AMAT = L1 hit time + L1 miss rate × (L2 hit time + L2 miss rate × memory penalty)`.
Do not mix local and global miss rates.

### Be able to do
- Decompose addresses into tag/index/offset.
- Trace accesses through a cache by hand.
- Show which line is evicted under FIFO and LRU.
- Track dirty bits and writebacks.
- Calculate hit/miss rates and AMAT.
- Explain why two caches with equal capacity can have different miss rates.

## 2. Cache controller and RTL

### Must know
- Finite-state machines: state, transition, output.
- Moore versus Mealy output logic.
- Ready/valid or request/response handshake.
- Synchronous memory interface assumptions.
- Tag RAM/data RAM organisation.
- Refill and writeback sequencing.
- Backpressure and request acceptance.
- Reset behaviour.
- Parameterisation and synthesizability.
- Assertions and testbench coverage.

### Be able to do
- Draw the FSM before coding.
- Explain every state and transition.
- Identify what happens if a request arrives while the controller is busy.
- Explain how dirty data is preserved.
- Read a GTKWave trace and identify the transaction lifecycle.
- Compare RTL output against a software reference model.

## 3. Branch prediction

### Must know
- Conditional branch and branch outcome.
- Static prediction.
- 1-bit predictor weaknesses.
- 2-bit saturating counter state machine.
- Local versus global history.
- GShare: global history XOR branch address indexing.
- Pattern history table (PHT).
- Aliasing and table-size effects.
- Branch Target Buffer (BTB) purpose.
- Prediction versus target prediction.
- Predictor update timing and speculative history recovery.

### Metrics
- Accuracy = correct predictions / total predictions.
- Misprediction rate = 1 − accuracy.
- Confusion matrix: TP, TN, FP, FN, with taken/not-taken definitions stated.
- Branch MPKI = branch mispredictions per 1,000 instructions.
- Branch penalty contribution to CPI = mispredictions per instruction × penalty cycles, under a clearly stated simplified model.

### Be able to do
- Update a 2-bit counter for a sequence of outcomes.
- Work through GShare indexing.
- Explain aliasing.
- Explain why a predictor can perform well on one workload and poorly on another.
- Distinguish direction prediction from target prediction.

## 4. Pipeline and speculation

### Must know
- IF, ID, EX, MEM, WB.
- Structural, data and control hazards.
- Forwarding and stalls.
- Branch resolution stage.
- Pipeline flush.
- Commit/retirement.
- Speculative versus committed state.
- Reorder buffer concept, even if not implemented.
- Precise architectural state.
- Squashed instructions.
- Speculation window and recovery latency.

### Be able to do
- Draw a cycle-by-cycle pipeline timing chart.
- Calculate CPI from total cycles and committed instructions.
- Identify useful, stalled and squashed cycles.
- Explain why a branch misprediction wastes work.
- Explain what must be restored after a misprediction.

## 5. Microarchitectural security and Spectre

### Must know
- Architectural state versus microarchitectural state.
- Transient execution.
- Speculative execution.
- Cache side channel.
- Timing distinguishability.
- Bounds-check bypass (Spectre Variant 1).
- Predictor training at a conceptual level.
- Secret-dependent cache footprint.
- Flush/reload and prime/probe as side-channel concepts; the project may model timing abstractly rather than implement real-machine attacks.
- Mitigation classes: fences, bounds-check hardening, isolation/partitioning, speculative-load restrictions.
- Threat model and security assumptions.

### Be able to explain
- Why squashing an instruction does not necessarily undo cache effects.
- Why a cache hit can be distinguishable from a cache miss in a timing model.
- Why a synthetic simulator result is not proof of a real CPU vulnerability.
- Which mitigation blocks which part of the modelled attack.
- What side channels remain outside the simulator.

## 6. Experimental methods and statistics

### Must know
- Independent, dependent and controlled variables.
- Baseline and treatment.
- Hypothesis and null hypothesis.
- Repeated trials.
- Mean, median, standard deviation and confidence intervals.
- Outlier investigation.
- Effect size.
- Correlation versus causation.
- Sensitivity analysis.
- Parameter sweep.
- Pareto frontier.
- Reproducibility and random seeds.

### Be able to do
- Change one variable at a time for a controlled experiment.
- Explain why a correlation does not prove causation.
- Report uncertainty when trials vary.
- Avoid misleading dual-axis plots and truncated axes.
- Interpret a result that contradicts the hypothesis.
- State limitations honestly.

## 7. Visualisation literacy

### Choose the chart for the question
- Time series: metric changing over cycles or time.
- Bar chart: compare a small number of configurations.
- Heatmap: values over two dimensions, such as cache sets × time.
- Scatter plot: relationship between two continuous metrics.
- Box plot/violin plot: distribution across repeated trials.
- Histogram/density: timing distributions.
- Stacked bar: composition of cycles or misses, if categories are mutually exclusive.
- Sankey: traffic flow, only if flow quantities are meaningful.
- Pareto plot: competing objectives such as leakage and performance overhead.

### Be able to do
- Label axes, units, sample size and configuration.
- Show baseline and treatment clearly.
- Explain what each chart proves and what it cannot prove.
- Link every chart to raw data and an experiment ID.
