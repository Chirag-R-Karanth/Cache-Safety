# MicroTrace — Step-by-Step Roadmap

The plan is organised around **working evidence**, not merely finishing code. The 12-week schedule assumes consistent work. If a milestone fails its exit criteria, fix it before moving on.

## Phase 0 — Project definition (Days 1–2)

### Tasks
- [ ] Create the Git repository and folder structure.
- [ ] Write a one-page problem statement.
- [ ] Define the research questions.
- [ ] Decide the simulation abstraction: cycle-level, five-stage in-order pipeline.
- [ ] Define what is implemented in SystemVerilog versus C++.
- [ ] Define all metrics before generating charts.

### Deliverables
- Problem statement.
- Scope and exclusions.
- Architecture block diagram.
- Initial glossary.
- Research question list.

### Exit criteria
Someone else can explain what the platform models, what it does not model, and what evidence it will produce.

---

## Week 1 — Learn and specify the architecture

### Understand
- Memory hierarchy and locality.
- Cache line, tag, index, offset, valid bit and dirty bit.
- Cache mapping and write policies.
- Branch outcome, predictor state and misprediction.
- Pipeline stages and control hazards.
- Architectural state versus microarchitectural state.
- Transient execution and cache timing side channels.

### Tasks
- [ ] Read a computer architecture text section on caches.
- [ ] Work through at least five address-decomposition problems by hand.
- [ ] Draw direct-mapped and set-associative cache structures.
- [ ] Draw a 2-bit saturating-counter state diagram.
- [ ] Read the Spectre paper's Variant 1 explanation.
- [ ] Write the assumptions and limits of your proposed simulator.

### Deliverables
- Architecture specification.
- Glossary.
- Literature notes with citations.
- Five manually solved cache examples.
- Initial experiment hypotheses.

### Exit criteria
You can explain tag/index/offset extraction, a cache miss lifecycle, a 2-bit predictor, a pipeline flush, and why a squashed instruction can leave a cache footprint.

---

## Week 2 — Cache reference simulator

### Implement
- [ ] Configurable cache capacity, line size and associativity.
- [ ] Address decomposition.
- [ ] Valid/tag lookup.
- [ ] Hit and miss handling.
- [ ] Direct-mapped cache.
- [ ] Set-associative cache.
- [ ] Fully associative cache.
- [ ] Deterministic memory-access trace input.

### Analyse
- [ ] Count hits, misses and accesses.
- [ ] Calculate hit rate and miss rate.
- [ ] Compare simulator output with hand calculations.
- [ ] Save raw results as CSV/JSON.

### Deliverables
- Working C++ reference cache.
- Unit tests.
- Address trace format.
- First cache performance chart.

### Exit criteria
All hand-calculated test traces match the simulator exactly.

---

## Week 3 — Cache policies and hierarchy

### Implement
- [ ] FIFO replacement.
- [ ] LRU replacement.
- [ ] Optional pseudo-LRU if time permits.
- [ ] Write-through and write-back.
- [ ] Write-allocate and no-write-allocate.
- [ ] Dirty-bit handling.
- [ ] L1 and L2 hierarchy.
- [ ] Explicit memory-latency model.

### Analyse
- [ ] Compare replacement policies on identical traces.
- [ ] Identify compulsory, capacity and conflict misses where the model supports classification.
- [ ] Calculate AMAT using explicitly documented hit/miss latencies.
- [ ] Plot cache-set pressure and eviction events.

### Deliverables
- Policy-complete cache simulator.
- Cache-set heatmap.
- Replacement-policy comparison.
- AMAT comparison.

### Exit criteria
Writeback, refill and eviction behaviour passes directed tests; all reported metrics have documented formulas.

---

## Week 4 — RTL cache controller

### Implement
- [ ] Define request/response interface and handshake rules.
- [ ] Draw the controller FSM.
- [ ] Implement lookup, victim selection, dirty check, writeback, refill and response states.
- [ ] Build directed testbenches.
- [ ] Add randomized tests.
- [ ] Inspect waveforms in GTKWave.
- [ ] Compare RTL behaviour with the C++ reference model.

### Analyse
- [ ] Measure controller latency in cycles.
- [ ] Count cycles spent in each FSM state.
- [ ] Identify bottleneck states.
- [ ] Capture representative waveforms.

### Deliverables
- Synthesizable SystemVerilog controller.
- Testbench suite.
- FSM diagram.
- GTKWave evidence.
- C++ versus RTL conformance report.

### Exit criteria
RTL and reference model agree for the same transaction traces, within the defined interface timing.

---

## Week 5 — Branch predictors

### Implement
- [ ] Static always-taken and always-not-taken baselines.
- [ ] 1-bit predictor.
- [ ] 2-bit saturating-counter predictor.
- [ ] GShare predictor.
- [ ] BTB model if indirect/target prediction is in scope.
- [ ] Trace-driven predictor interface.

### Analyse
- [ ] Accuracy and misprediction rate.
- [ ] Confusion matrix for taken/not-taken.
- [ ] Accuracy over time.
- [ ] Sensitivity to table size and history length.
- [ ] Aliasing effects.

### Deliverables
- Predictor library.
- Identical trace benchmark suite.
- Predictor comparison dashboard.
- Written interpretation of where each predictor wins and loses.

### Exit criteria
All predictors consume the same branch traces and use clearly defined update timing.

---

## Week 6 — Five-stage pipeline model

### Implement
- [ ] IF, ID, EX, MEM and WB stages.
- [ ] Instruction trace or small instruction subset.
- [ ] Data hazard detection.
- [ ] Forwarding.
- [ ] Load-use stall.
- [ ] Branch resolution stage.
- [ ] Predictor integration.
- [ ] Flush and recovery.
- [ ] Cycle-accurate event log.

### Analyse
- [ ] CPI and IPC.
- [ ] Stall cycles by cause.
- [ ] Branch penalty.
- [ ] Useful versus squashed instructions.
- [ ] Pipeline occupancy timeline.

### Deliverables
- Working five-stage in-order pipeline model.
- Pipeline timeline visualisation.
- Hazard and recovery tests.

### Exit criteria
Cycle counts match manually traced short instruction sequences.

---

## Week 7 — Speculative execution model

### Implement
- [ ] Track speculative instructions and their branch context.
- [ ] Separate speculative and committed architectural state.
- [ ] Model speculative loads.
- [ ] Model branch resolution.
- [ ] Squash younger instructions on misprediction.
- [ ] Preserve explicitly modelled cache side effects.
- [ ] Record a per-cycle event trace.

### Analyse
- [ ] Speculation window length.
- [ ] Squashed instruction count.
- [ ] Recovery cycles.
- [ ] Cache changes caused by transient operations.
- [ ] Sensitivity to branch resolution latency.

### Deliverables
- Speculative execution engine.
- Speculation timeline.
- Correctness tests for commit and squash behaviour.

### Exit criteria
A squashed instruction cannot commit architectural results, but the model can retain the explicitly modelled microarchitectural cache effect.

---

## Week 8 — Controlled Spectre Variant 1 demonstration

### Scope
Use a **synthetic victim and synthetic secret inside the simulator**. This is a model-level demonstration, not an attempt to extract secrets from a real system.

### Implement
- [ ] Synthetic bounds-checked victim.
- [ ] Predictor training phase.
- [ ] Mispredicted transient path.
- [ ] Secret-dependent cache-line footprint.
- [ ] Cache observation/timing model.
- [ ] Recovery procedure and confidence calculation.
- [ ] Baseline non-speculative control experiment.

### Analyse
- [ ] Recovery accuracy over repeated trials.
- [ ] Timing/latency distributions for hit and miss classes.
- [ ] False-positive and false-negative observations.
- [ ] Effect of model parameters on leakage distinguishability.

### Deliverables
- Reproducible Spectre V1 simulation.
- Attack timeline.
- Leakage analysis plots.
- Documented assumptions and limitations.

### Exit criteria
The synthetic secret is not available through ordinary architectural execution, but the controlled model demonstrates a measurable cache-side-channel signal.

---

## Week 9 — Mitigations

### Model
- [ ] Speculation barrier / fence abstraction.
- [ ] Bounds-check hardening.
- [ ] Cache partitioning or isolation abstraction.
- [ ] Optional speculative-load restriction abstraction.

### Analyse
- [ ] Repeat the same attack workload with each mitigation.
- [ ] Measure leakage reduction.
- [ ] Measure IPC/CPI overhead.
- [ ] Check for residual leakage.
- [ ] Compare mitigation effectiveness under multiple configurations.

### Deliverables
- Mitigation comparison table.
- Leakage-versus-overhead plot.
- Pareto frontier.
- Clear statement of what each modelled mitigation does and does not represent.

### Exit criteria
Baseline and mitigated runs use identical workload and configuration except for the mitigation under test.

---

## Week 10 — Dashboard integration

### Build
- [ ] Overview page.
- [ ] Cache laboratory.
- [ ] Branch predictor laboratory.
- [ ] Pipeline/speculation explorer.
- [ ] Security laboratory.
- [ ] Experiment comparison page.
- [ ] Configuration controls.
- [ ] Drill-down from chart to raw event trace.

### Deliverables
- Interactive dashboard connected to actual saved experiment outputs.
- No hard-coded demonstration metrics in final views.
- Exportable chart data.

### Exit criteria
A user can configure a run, execute it, inspect metrics, and trace a chart point back to the experiment and raw data.

---

## Week 11 — Research-grade analysis

### Tasks
- [ ] Freeze the experiment matrix.
- [ ] Run repeated trials where randomness exists.
- [ ] Save raw data and metadata.
- [ ] Calculate summary statistics and uncertainty.
- [ ] Run sensitivity analysis.
- [ ] Generate correlation analysis where scientifically justified.
- [ ] Generate Pareto comparisons.
- [ ] Investigate unexpected results.
- [ ] Re-run failed or anomalous experiments.

### Deliverables
- Reproducible experiment bundle.
- Final plots.
- Results tables.
- Interpretation notes.
- Limitations section.

### Exit criteria
Every major claim in the report points to a saved experiment and a reproducible analysis.

---

## Week 12 — Final report and demonstration

### Tasks
- [ ] Run full regression suite.
- [ ] Freeze source version and experiment configuration.
- [ ] Write methods and results.
- [ ] Explain model assumptions and limitations.
- [ ] Prepare architecture diagrams.
- [ ] Prepare 8–12 minute demonstration.
- [ ] Prepare likely viva questions.
- [ ] Tag a release.

### Deliverables
- Source code and build instructions.
- Technical report.
- Presentation.
- Demo script.
- Experiment data and generated plots.
- Reproducibility instructions.

### Exit criteria
A reviewer can build the project, reproduce at least the main experiments, and understand what conclusions the model supports.
