# Development replay headroom

Status: IN PROGRESS. Created 2026-10-06.

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

Bounded tests preserve mandatory membership, stable identity ranking,
exact result counts and all frozen bindings. Digest, snapshot, profile,
acquisition and fidelity tampering still fail, including corruption in
unselected records. Injected disagreements and native drift still fail.
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

The full-corpus storage evidence in
`reports/20261006-native-replay-storage/` is immutable historical evidence.
Its full native and whole-command timings are separate from this selected
development phase. Fresh profiling selects optimizations; dropping binding
checks, caching a prior success, changing SQL or weakening native evidence
does not satisfy this task. Timing runs use an idle host.
