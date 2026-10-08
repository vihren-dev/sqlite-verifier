# Linux stage wall and CPU diagnostic

This is diagnostic evidence. It does not replace the fresh Linux acceptance
miss of 39.57022682100069 seconds. The task remains **IN PROGRESS**.

The coordinator authorized one instrumented phase after the complete fresh
receipts and their evidence review. Session 81515 finished with exit 0. Its
instrumented report phase took 39.26042659499217 seconds; the outer call took
40.081648631 seconds. The process-group bound stayed at 120 seconds. No phase
was rerun, no conformance runtime was rebuilt, and no production source changed.

| Parent stage | Calls | Wall seconds | Parent CPU seconds | Reaped child CPU seconds |
|---|---:|---:|---:|---:|
| Full generic loading | 1 | 20.791746283 | 20.736654 | 0 |
| Native development workers | 1 | 17.867181973 | 0.333035 | 5.532435 |
| Runtime binding | 1 | 0.287032796 | 0.286570 | 0 |
| Current-model classification | 2 | 0.258761494 | 0.173302 | 0.093372 |
| Identity selection | 1 | 0.046736350 | 0.046587 | 0 |
| Synthetic binding/loading | 1 | 0.005227810 | 0.005192 | 0 |
| Report binding | 2 | 0.000946490 | 0.000949 | 0 |

CPU columns sum independently recorded user and system counters. Loading used
parent CPU for almost all its observed wall duration. The native worker stage
also has substantial wall duration. Parallel child CPU can exceed wall time.
A difference between wall and summed CPU is not a measurement of I/O, fsync
or storage latency. This diagnostic records no per-function loading profile,
worker utilization, syscall or fsync attribution. It does not prove savings
for a proposed optimization.

## Inputs and observer

The exact source is `5d15607fdf78d0a209b539ca158939739b54d377`, and the
existing runtime is
`/nix/store/rhinzr7jq41azsh6s8i8dmndi7idnv3k-sqlite-verifier-conformance`.
The before/after source, complete runtime, archive, Python, Lean and native
library identities match each other and the
[fresh Linux receipt](../20261007-development-replay-headroom-acceptance/README.md).
The same full bindings, 4378-case denominator and 184 selected identities,
profiles, SQL, native observations and verdicts remain unchanged. All 184
native comparisons passed; all current-model classifications remain
`MODEL_UNSUPPORTED`. This does not establish agreement within supported model
semantics.

Three public helper files are retained with their exact hashes. A main guard
keeps spawned workers from restarting the observer. The helper wraps only the
report's existing `runtime_binding`, `load`, `bound_records`, `select`,
`replay_native_cases`, `checked_replay` and `binding` names in the parent.
Each wrapper records monotonic wall duration, `RUSAGE_SELF` and
`RUSAGE_CHILDREN` user/system deltas, and the original failure type. It retains
the original return or exception. `RUSAGE_CHILDREN` accounts for direct
children reaped in that call; it is not a simultaneous per-worker trace.
The unchanged two-worker helper joins its spawned pool inside the observed
`replay_native_cases` call. A bounded pure preflight checks return and exception
preservation without invoking a report.

The new private root is
`/var/tmp/sqlite-verifier-t04c-stages-20261007.ukouzpmj`. Its selected ordinary
file storage is `diagnostic/native-storage`, on ext4 `/dev/md127` mounted
`rw,noatime`. All 184 actual unique `case.db` paths and cleanup are retained.
UTC boundaries are `2026-10-07T08:26:35.791666+00:00` and
`2026-10-07T08:27:15.873303+00:00`; monotonic nanoseconds are
`421241391951204` and `421281473599835`. Full load, machine, memory,
capacity and filesystem observations remain in the original receipt.
Full identity reads preceded and followed the phase outside its timing.
OS file caches were not flushed, and residency was not observed.

## Retention checks

All 20 original artifacts have compressed and uncompressed SHA-256 entries
in `raw-sha256.json`. They include the full report, original command streams
and capture log, actual paths and timestamps, complete before/after identities,
all stage observations, helpers, preflight observations and the remote
retrieval manifest. All 13 retrieved original hashes match that remote
inventory, which also observed cleaned storage. The prior fresh receipts,
diagnostic evidence and frozen inputs remain unchanged.

Run the bounded checks without native replay or builds:

```sh
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-linux-stages/validate.py
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-linux-stages/check_mutations.py
```

The validator recomputes every stage's wall and CPU totals and verifies the
complete unchanged binding, helper, timestamp, fixture and transport evidence.
The mutation checks refuse a missing worker-stage observation and an altered
child CPU counter. No test assumes that summed parallel CPU is below wall time.
