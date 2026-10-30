# Architecture Specification

## 1. Design principle

Separate four layers:

1. **Simulation core** — deterministic model of cache, predictor, pipeline and speculation.
2. **Experiment runner** — generates configurations, executes runs and records metadata.
3. **Analysis pipeline** — validates, aggregates and derives metrics from raw outputs.
4. **Dashboard** — queries saved results and visualises them.

The dashboard must not invent metrics or contain a second implementation of the architecture model.

## 2. Data flow

```text
Workload / instruction trace
          |
          v
   Configuration file
          |
          v
     Experiment runner
          |
          v
   C++ simulation engine
          |
          +------> Event trace (JSONL)
          |
          +------> Raw metrics (JSON)
          |
          v
   Validation + analysis scripts
          |
          +------> Results table (CSV/Parquet)
          |
          +------> Derived metrics
          |
          v
     Dashboard / report
```

## 3. Suggested module boundaries

### C++ simulation core
- `CacheConfig`
- `CacheLine`
- `CacheSet`
- `Cache`
- `CacheHierarchy`
- `ReplacementPolicy`
- `BranchPredictor`
- `Pipeline`
- `SpeculationTracker`
- `EventRecorder`

### RTL
- Request/response interface.
- Tag/data storage interface.
- Controller FSM.
- Refill/writeback interface.
- Testbench and assertions.

### Experiment runner
- Load experiment matrix.
- Validate configuration.
- Assign experiment ID and seed.
- Run simulator.
- Capture exit status and runtime.
- Save raw output and metadata.
- Never overwrite prior experiment results.

### Analysis
- Validate schema.
- Reject incomplete or invalid runs.
- Compute derived metrics.
- Generate chart-ready datasets.
- Save analysis script version.

### Dashboard
- Read saved results.
- Filter by experiment, workload and configuration.
- Display chart and metadata.
- Drill down to event traces.
- Export filtered data.

## 4. Suggested configuration example

```json
{
  "experiment_id": "C1_assoc_traceA",
  "workload": "traceA",
  "seed": 12345,
  "cache": {
    "capacity_bytes": 16384,
    "line_size_bytes": 64,
    "associativity": 4,
    "replacement": "LRU",
    "write_policy": "write_back",
    "allocation_policy": "write_allocate"
  },
  "memory": {
    "l1_hit_cycles": 1,
    "l2_hit_cycles": 8,
    "memory_penalty_cycles": 80
  }
}
```

This is an example schema, not a claim that these parameters represent a particular commercial CPU.

## 5. Event trace principles

Each event should include:
- Cycle number.
- Event type.
- Instruction ID where relevant.
- PC where relevant.
- Address where relevant, if safe and useful in the synthetic model.
- Speculation context.
- Component.
- Relevant before/after state.

Use JSON Lines for large traces: one JSON object per line.

## 6. Reproducibility metadata

Every run must save:
- Experiment ID.
- Timestamp.
- Git commit hash.
- Simulator version.
- Configuration file.
- Workload identifier and checksum.
- Random seed.
- Start/end status.
- Raw metrics.
- Output file paths.
- Analysis version.

## 7. Model boundaries

Document whether the simulator models:
- Cycle accuracy or abstract latency.
- In-order or out-of-order execution.
- Blocking or non-blocking caches.
- One or multiple outstanding misses.
- Coherence or no coherence.
- TLB/page translation or no TLB.
- Realistic timing noise or deterministic latency.
- Predictor state sharing or isolation.

Do not imply support for features that are not implemented.
