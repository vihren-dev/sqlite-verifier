# Full native replay storage status

Status: IN PROGRESS. Created 2026-10-06.

Task: [full native replay storage](20261006-native-replay-storage.task.md).
Source: [issue #37](https://github.com/vihren-dev/sqlite-verifier/issues/37).

Relevant files: `conformance/native_record.py`, `conformance/corpus.py`,
`conformance/progress.py`, `tools/check_resources.py`, `justfile`,
`docs/conformance-progress.md`, and the historical
`reports/20261005-adr5-review-execution/` evidence.

## Progress

- 2026-10-06: Read the public issue, retained platform receipts and fixture
  lifecycle. Full replay uses ambient `TemporaryDirectory`; its CLI retains
  neither resource conditions nor actual fixture paths. Invalid `TMPDIR` can
  fall back to another directory. The historical tmpfs run and the resource
  helper already use a 10 GiB free-space policy. Created this task before code
  changes in a separate workspace based on `4a425828`.
- 2026-10-06: Linux timing measurements are pending explicit idle confirmation
  because the host is running separate toolchain validation. The completed
  catalog workspace and its pending review log remain untouched.

## Validation and review

Pending. Use the existing pinned Nix shell and explicit runtime root for local
checks. Preserve every review outcome in the append-only review log.
