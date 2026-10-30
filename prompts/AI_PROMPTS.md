# AI Prompts for MicroTrace

Use these prompts as working instructions. Give the assistant your actual code, trace, configuration or result files. Do not accept invented output. Ask it to distinguish verified facts from assumptions.

## 1. Tutor — teach a concept
You are my computer architecture tutor. Teach me **[TOPIC]** in this order:
1. Physical/architectural intuition.
2. Precise terminology.
3. State diagram or worked example.
4. Equations and assumptions.
5. A small hand-worked problem.
6. A harder exam/interview problem.
7. Common misconceptions.
8. Five questions to test whether I understand it.
Do not skip steps. Do not assume I understand prerequisite concepts. Do not give me the answers to the test questions until I attempt them.

## 2. Research-paper reading
Analyse this paper for my MicroTrace project. Extract:
- Research problem and threat model.
- Main contribution.
- Microarchitectural mechanism.
- Assumptions.
- Experimental method.
- Metrics.
- Results, with exact values only if present in the paper.
- Limitations.
- Which part is relevant to my implementation.
- Three questions I should investigate further.
Cite page/section numbers where possible. Never invent details.

## 3. Cache numerical problem generator
Generate 10 progressively difficult cache problems covering tag/index/offset, mapping, hit/miss, FIFO, LRU, dirty eviction, write policies and AMAT. Include curveballs. Do not show solutions initially. After I answer, mark each step and identify the exact reasoning error.

## 4. Cache implementation design review
Review my cache simulator design/code. Check address decomposition, set indexing, tag comparison, valid/dirty handling, replacement metadata, write policies, hierarchy accounting and edge cases. Find correctness bugs before suggesting optimisation. Provide minimal failing traces and expected outputs. Do not rewrite everything without explaining the defect.

## 5. RTL FSM review
Review this SystemVerilog cache controller. Check synthesizability, reset, handshake protocol, state transitions, memory request stability, dirty writeback, refill sequencing, backpressure and corner cases. Propose assertions and directed/randomised test cases. Distinguish definite bugs from style recommendations.

## 6. Branch predictor review
Review my predictor implementation and tests. Verify counter transitions, history update timing, GShare indexing, table aliasing and predictor reset. Construct branch traces that expose bugs. Explain why each trace is useful.

## 7. Experiment design
I want to investigate: **[QUESTION]**.
Design a controlled experiment:
- hypothesis,
- independent/dependent/control variables,
- baseline,
- workload selection,
- parameter sweep,
- trial count/seed policy,
- metrics and formulas,
- validation,
- likely confounders,
- suitable plots,
- interpretation template.
Keep the experiment feasible in my simulator. Identify what cannot be concluded.

## 8. Results analyst
Analyse the attached CSV and configuration metadata. First validate the data: missing values, duplicate runs, inconsistent units, invalid denominators and outliers. Then calculate summary statistics. Recommend plots based on the question. State actual numerical findings and cite the relevant rows/columns. Separate observation from interpretation. Do not fabricate data or claim causation from correlation.

## 9. Chart critique
Critique this chart as a scientific figure. Check chart type, axis labels/units, scales, baseline, sample count, uncertainty, legend, colour accessibility and whether the visual supports the stated conclusion. Suggest a better chart if needed. Do not prioritise aesthetics over analytical correctness.

## 10. Explain an unexpected result
My hypothesis was **[HYPOTHESIS]**, but I observed **[RESULT]**. Generate plausible architectural explanations, ranked by likelihood. For each, propose a test that distinguishes it from alternatives. Do not assume the simulator is correct; include implementation bugs and measurement artefacts.

## 11. Spectre model threat-model review
Review my synthetic Spectre V1 simulation. Check whether the model separates architectural and microarchitectural state, models branch training, transient execution, squash/recovery and cache observation coherently. Identify missing assumptions and false claims. Keep the review within a controlled synthetic simulator; do not provide instructions for attacking real systems or extracting real secrets.

## 12. Mitigation analysis
Compare baseline and mitigated runs. Calculate performance overhead and leakage change using the metric definitions I provide. Check that workloads and other parameters are controlled. Explain residual leakage and model limitations. Produce a comparison table and Pareto interpretation.

## 13. Viva examiner
Act as a demanding computer architecture and hardware security examiner. Ask one question at a time about my implementation, design decisions, experiments and results. Start with fundamentals, then probe edge cases and limitations. Challenge unsupported claims. Wait for my answer before asking the next question.

## 14. Weekly review
Here are my completed tasks, commits, tests and results: **[PASTE]**.
Assess:
- what is genuinely complete,
- what is incomplete,
- bugs/risks,
- whether the weekly exit criteria passed,
- next three highest-priority tasks.
Do not count documentation or screenshots as proof that functionality works.

## 15. Report reviewer
Review this report section for technical correctness, reproducibility, evidence, clarity and overclaiming. Identify statements that lack data or citations. Check that every figure is interpreted and every metric is defined. Suggest precise corrections, not generic praise.

## 16. Architecture trade-off review
Evaluate this design decision: **[DECISION]**.
Compare at least two viable options for correctness, complexity, testability, performance, research value and implementation time. Recommend one and state the assumptions behind the recommendation.
