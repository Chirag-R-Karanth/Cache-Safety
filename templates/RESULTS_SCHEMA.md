# Results and Metadata Schema

This document defines the minimum record for a completed simulator run. Keep one record per **experiment × configuration × workload × trial**. Store detailed cycle/event records separately as JSONL. Treat completed raw outputs as immutable.

## Required run metadata

| Field | Type | Required | Definition |
|---|---|---:|---|
| `experiment_id` | string | yes | Stable ID linking the run to the experiment register. |
| `run_id` | string | yes | Unique ID for this exact configuration/workload/trial execution. |
| `timestamp_utc` | ISO-8601 string | yes | Run start timestamp in UTC. |
| `git_commit` | string | yes | Source commit used for the run. |
| `simulator_version` | string | yes | Released version or explicit development identifier. |
| `workload_id` | string | yes | Stable workload name. |
| `workload_hash` | string | yes | SHA-256 of the exact workload input. |
| `seed` | integer or null | yes | Seed; null only when the run is deterministic and no RNG is used. |
| `trial` | integer | yes | 1-based trial number. |
| `config_json` | object or path | yes | Complete immutable configuration or path to it. |
| `status` | enum | yes | `success`, `failed`, or `invalid`. |
| `runtime_ms` | number or null | yes | Host wall-clock runtime, not simulated CPU cycles. |
| `event_trace_path` | string or null | yes | JSONL event trace path, or null when event tracing is disabled. |

## Cache metrics

- `accesses`, `hits`, `misses`: non-negative integer counts.
- `hit_rate`, `miss_rate`: fractions in [0, 1], calculated from counts.
- `writebacks`: non-negative integer count of dirty evictions written to the next level.
- `l1_misses`, `l2_misses`: non-negative integer counts; state whether L2 misses are conditional on an L1 miss.
- `amat_cycles`: numeric average memory access time in simulated cycles; document the hierarchy formula.

Required invariants when cache metrics are applicable:
- `accesses = hits + misses`.
- `hit_rate = hits / accesses` and `miss_rate = misses / accesses` when accesses > 0.
- Rates are null, not zero, when the denominator is zero.

## Branch metrics

- `branches`, `correct_predictions`, `mispredictions`: non-negative integer counts.
- `accuracy`: fraction in [0, 1]; null when no predictions were made.
- `mpki`: mispredictions per 1,000 committed instructions; null when the denominator is zero.
- `predictor_storage_bits`: non-negative integer count, including only structures stated in the model.

Required invariant: `branches = correct_predictions + mispredictions` when every branch is predicted exactly once.

## Pipeline metrics

- `committed_instructions`, `total_cycles`, `stall_cycles`, `recovery_cycles`, `squashed_instructions`: non-negative integer counts.
- `cpi = total_cycles / committed_instructions`.
- `ipc = committed_instructions / total_cycles`.
- CPI/IPC are null when their denominator is zero.

## Synthetic security metrics

- `synthetic_secret_trials`, `correct_recoveries`: non-negative integer counts.
- `recovery_accuracy = correct_recoveries / synthetic_secret_trials`, null when no trial exists.
- `false_positive_rate`, `false_negative_rate`: fractions in [0, 1], with class definitions and denominators stated.
- `leakage_metric_name`, `leakage_metric_value`: named metric and numeric value; document direction and interpretation. Do not label an arbitrary composite as a universal security score.

## Mitigation metrics

- `mitigation_id`: stable mitigation identifier, or an explicit baseline identifier.
- `performance_overhead_pct`: percentage relative to a named baseline, with formula recorded.
- `leakage_reduction_pct`: percentage relative to a named baseline only when the leakage metric's zero and direction make this meaningful. Also report absolute values.

## Data rules

1. Preserve raw numerators and denominators for every derived rate.
2. Use null for not applicable or undefined; never use zero to mean missing.
3. Keep counts as integers and identify every unit.
4. Store rates consistently as fractions in [0, 1]; convert to percentages only for display.
5. Reject inconsistent records rather than silently repairing them.
6. Do not combine records from different metric-definition versions without an explicit migration.
7. A failed or invalid run remains in the archive with its status and logs; do not delete it.
8. CSV files are flat exports. Keep full nested configuration in immutable JSON files and reference them by path or hash.
