# Development replay headroom

Status: IN PROGRESS. Created 2026-10-06.

Latest complete acceptance is in
[the 2026-10-07 receipt](../reports/20261007-development-replay-headroom-acceptance/README.md).
On reviewed publication-base source, macOS took 21.434975332995236 seconds
and Linux took 39.57022682100069 seconds. Both retain complete bindings,
timestamps and actual fixture paths. Linux still misses the target. Earlier
observations below remain historical evidence; this task is not DONE.
The later [parent/child CPU diagnostic](../reports/20261007-development-replay-linux-stages/README.md)
records current loading and worker-stage costs on the same source/runtime.
Its instrumented result is separate from acceptance.

The one-run measurement record is in
[the dated receipt](../reports/20261006-development-replay-headroom/README.md).
Linux took 49.70655691897264 seconds and misses the target below. The macOS
phase took 23.699742582997715 seconds but lost ancillary receipt fields after
the phase completed. These observations do not satisfy both-platform
acceptance; the task is not DONE.
The later [Linux diagnostic](../reports/20261006-development-replay-linux-profile/README.md)
identifies both CPU loading and native non-CPU time. Its instrumented timings
are separate from acceptance results; it does not change the outcome below.

## Outcome

The fresh development replay phase finishes in less than 30 seconds on
macOS arm64 and Linux amd64. This includes full frozen-input loading and
binding checks, native replay of the selected cases, and current-model
classification. The measurement identifies the selected ordinary-file
temporary storage and retains actual timing headroom.

All authored and synthetic cases remain mandatory. Policy version 1 keeps
the same 184 v5 selected identities, one case from each nonempty upstream
source shard, and eight additional cases ranked only by source and name.
Native observations, exact execution profiles, unsupported classifications,
and disagreement and harness-error failure semantics retain their meaning.
The complete frozen v1–v5 bytes and denominators remain unchanged.

Source: [issue #33](https://github.com/vihren-dev/sqlite-verifier/issues/33).

## Acceptance

Actual bounded executions on both supported platforms retain corpus,
runtime and profile digests, selection policy and selected identities,
case verdicts, explicit storage conditions and fresh phase timings. They
are uncached invocations and pass the less-than-30-second target.
The unchanged 184 identities and their verdicts match retained v5 evidence.
Historical v4 replay keeps its 100-case membership.
Bounded receipt checks distinguish a valid measurement from a speed-target
pass. They refuse corrupted selected identities, native-library hashes,
duplicate actual fixture paths and a target flag that hides a Linux miss.
An instrumented diagnostic retains wall time and parent and reaped direct-child
CPU for each existing top-level report stage, including the development worker
helper. It preserves original returns and exceptions, complete binding/path
evidence and the configured process-group bound. Its result is diagnostic
evidence. Summed parallel CPU can exceed wall time; differences between wall
and CPU do not measure I/O or fsync time.
A load-only cProfile diagnostic calls `conformance.corpus.load` once for all
frozen v5 bindings. It retains original pstats, per-function/caller views,
loaded count/profiles/identities, original streams and before/after source,
frozen-input, Python and helper hashes. Its instrumented load duration is
separate from acceptance and timing comparisons. The helper uses a main guard
and a name that cannot shadow Python's `profile` module. It invokes no native
replay or model execution, and retains the same process-group guard.

Bounded tests preserve mandatory membership, stable identity ranking,
exact result counts and all frozen bindings. Digest, snapshot, profile,
acquisition and fidelity tampering still fail, including corruption in
unselected records. Injected disagreements and native drift still fail.
Bounded snapshot expansion matches the actual canonical expanded JSON byte
length at the exact limit and one byte beyond it. Repeated and empty
snapshots, escaped/multibyte metadata, nested independent mutations and
malformed or unused pools retain their checks. The default expansion
primitive remains unbounded; shard loading enforces both stored and logical
case limits before selecting any replay cases.
Reference-size counting may skip JSON encoding only when an ordinary mapping,
ordinary sole key and ordinary ASCII alphanumeric string prove exact canonical
size as the fixed key/punctuation bytes plus string length. Mapping, key and
string subclasses and escaped/multibyte/other shapes retain the existing
serializer path. Independent canonical JSON oracles check those cases, exact
and one-byte-short limits, negative empty-snapshot deltas and preserved subtype
rendering. Validation order and the default unbounded primitive remain intact.
Snapshot reconstruction matches an independent canonical JSON oracle for
scalar values, signed zero, escaped text, caller-owned JSON subclasses and
reused nested mutable objects. Canonical JSON decoding occurs once per
validated pool entry; every occurrence still has an independent mutable tree.
Independent development cases may replay in two spawned worker processes.
Every SQL statement, profile, controlled clock and durability setting retains
its meaning. Failures and fixture paths retain input order; native exception
codes survive transport. Normal failures and worker crashes clean private file
trees and fail the tier. Configured outer timeouts stop the complete worker
process group at the unchanged bound. Actual-native checks compare serial
evidence, isolate UTC clocks from a non-UTC parent and retain failure paths.
Storage audit checks exercise actual native fixtures. Relevant corpus,
tier and Nix target checks retain the owner-approved 120-second phase bound
from `06a1e297`; the separate acceptance target remains less than 30 seconds.

## Constraints

`conformance/replay_tiers.py` owns selection, fresh phase timing and the
development report. `conformance/corpus.py`, `corpus_shards.py`,
`corpus_evidence.py` and `corpus_acquisition.py` own full loading and binding
validation. `native_storage.py` expands shared snapshots and checks their
size and digests. `native_replay.py` performs frontend admission and typed
output validation. `native_record.py` owns native temporary fixtures.
`tests/conformance_sample_test.py` runs the same fresh CLI as the sample
Nix target; `build-support/tests.nix` binds that target's inputs.
Canonical JSON remains authoritative for snapshot hashes, logical byte counts
and normalization. Any internal binary copies are generated only from decoded
canonical JSON in the current invocation. External binary data is not an input.
`native_workers.py` supplies only the development helper; `corpus.native_replay`
remains the flexible serial primitive for full replay and library callers.
Worker processes inherit the configured timeout's process group. Both real
tier CLI tests use `tests.runtime_support.run_command` to stop that group.
The sample and model Nix inputs include the worker module. Each native case
uses its own ordinary SQLite fixture beneath a parent-owned private directory;
the helper also supports explicit storage and actual fixture-path auditing.

The full-corpus storage evidence in
`reports/20261006-native-replay-storage/` is immutable historical evidence.
Its full native and whole-command timings are separate from this selected
development phase. Fresh profiling selects optimizations; dropping binding
checks, caching a prior success, changing SQL or weakening native evidence
does not satisfy this task. Timing runs use an idle host.
Fresh receipts retain host load and OS-cache qualifications. Full identity
reads occur outside phase timing; cache residency is not claimed. A filesystem
observation made after a phase is labeled after-only, and does not replace
its original before/after observations. Missing failed-preflight timestamps
or traceback bytes remain explicit limitations. No unchanged phase restarts
follow an observation failure or target miss.
