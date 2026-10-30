# Results and Metadata Schema

Store one record per experiment/configuration/workload/trial. Store detailed events separately in JSONL.

## Required metadata
- `experiment_id`: stable unique ID.
- `timestamp_utc`: ISO-8601 timestamp.
- `git_commit`: source revision.
- `simulator_version`: version identifier.
- `workload_id`: stable workload name.
- `workload_hash`: checksum of input trace.
- `seed`: integer or null for deterministic runs.
- `trial`: trial number.
- `config_json`: complete configuration or path to immutable config file.
- `status`: success, failed, invalid.
- `runtime_ms`: host execution time; not simulated CPU time.

## Cache metrics
- `accesses`
- `hits`
- `misses`
- `hit_rate`
- `miss_rate`
- `writebacks`
- `l1_misses`
- `l2_misses`
- `amat_cycles`

## Branch metrics
- `branches`
- `correct_predictions`
- `mispredictions`
- `accuracy`
- `mpki`
- `predictor_storage_bits`

## Pipeline metrics
- `committed_instructions`
- `total_cycles`
- `cpi`
- `ipc`
- `stall_cycles`
- `recovery_cycles`
- `squashed_instructions`

## Security metrics
- `synthetic_secret_trials`
- `correct_recoveries`
- `recovery_accuracy`
- `false_positive_rate`
- `false_negative_rate`
- `leakage_metric_name`
- `leakage_metric_value`

## Mitigation metrics
- `mitigation_id`
- `performance_overhead_pct`
- `leakage_reduction_pct`

## Rules
- Do not store a derived metric without retaining its raw numerator/denominator.
- Use null for not-applicable metrics; do not use zero to mean missing.
- Document whether rates are fractions or percentages.
- Keep cycle counts as integers.
- Include units in field documentation.
- Never silently change metric definitions between experiment versions.
