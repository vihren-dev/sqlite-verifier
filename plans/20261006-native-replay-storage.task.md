# Full native replay storage

Status: IN PROGRESS. Created 2026-10-06.

## Outcome

Full native corpus replay uses an explicitly selected temporary-storage
directory. The corpus and freezer CLIs and `just conformance-corpus` make that
input visible. The freezer retains an operational receipt beside its output,
without adding storage conditions to frozen observations or execution profiles.
Its report records the selected path, available storage, actual ordinary-file
fixture paths, timing, execution command and unchanged source, corpus, runtime
and native-library bindings. A missing, invalid, unwritable or insufficient
storage directory produces an actionable diagnostic before expensive replay.

SQLite keeps ordinary file-backed databases, the same SQL, execution profiles,
native identities and typed observations. Frozen corpora v1–v5 remain unchanged.
Model-only progress is identified as such and does not imply fresh native
replay. Full-native invocation guidance makes the Linux tmpfs opt-in explicit.

Source: [issue #37](https://github.com/vihren-dev/sqlite-verifier/issues/37).

## Acceptance

Bounded tests exercise explicit path selection through real native recording
and the corpus CLI. They check the reported fixture paths and exact preserved
observations, and reject absent, invalid and insufficient storage. The existing
10 GiB development resource policy supplies the capacity threshold. Tests
verify cleanup and the unchanged bindings in a successful small full replay.
The freezer uses the selected root and retains a separate receipt for its
successful native replay without changing its manifest or case format.
Each subprocess has a short timeout.

Retained Linux measurements compare a short authored case and the longest
upstream setup prefixes from two different sources on ext4 and tmpfs, selected
by input identity before timing. All six complete fresh records must be equal
across storage and their native observations must equal frozen evidence. Each
case has a 60-second bound. The retained diagnosis explains the measured
file-backed storage cost without claiming ext4 performance or crash durability.

One actual full v5 native run has the existing 420-second bound and retains
command, storage/resource checks, all actual fixture paths, timing and unchanged
input bindings. Its 4,376 native observation comparisons must pass. Preserve
the historical 420- and 900-second timeout receipts and the passing ext4 sample.
Linux timing runs wait until the shared validation host is idle.

## Constraints

`conformance/native_record.py:record_sql` owns each temporary file fixture.
`conformance/corpus.py:native_replay` compares fresh and frozen observations;
its CLI performs full replay. `conformance/progress.py` classifies frozen
evidence without a fresh native check. `tools/check_resources.py` supplies the
existing capacity policy. `justfile` and `docs/conformance-progress.md` describe
the user commands. The existing diagnosis and timeout records are in
`reports/20261005-adr5-review-execution/`. `conformance/freeze_corpus.py` performs
another full native replay before publishing newly frozen evidence.

Small library recordings and test samples retain their flexible ambient-storage
primitive. Full native CLI runs bind their selected root directly to fixture
creation, rather than relying on tempfile's fallback from an invalid `TMPDIR`.
Storage audit data belongs in new execution reports, never in frozen native
observations. Replay acceleration is a separate task.
