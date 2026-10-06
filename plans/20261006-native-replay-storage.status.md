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
- 2026-10-06: Full corpus and freezer CLIs now require an explicit temporary
  root. Each native file fixture can record its actual database path. Full-run
  reports retain capacity, device, paths, native timing, original interpreter
  arguments and unchanged source/corpus/record/runtime/library bindings.
  The freezer writes a separate operational receipt; its manifest, profiles
  and native wire format are unchanged. The existing 10 GiB resource guard
  checks the selected filesystem and verifies directory creation.
- 2026-10-06: Nix daemon access became restricted during validation. Stopped
  and received authorization to use the established execution escalation for
  required Nix checks. No configuration or dependency change was needed.

## Validation and review

- Ran checks through the pinned shell at
  `nix develop path:/Users/tzankomatev/work/sqlite-verifier/nix --command`, with
  runtime `/nix/store/2pm5l48v8lk5v3p1yqbc3hx3jj1w2ylr-sqlite-verifier-conformance`.
- `timeout 45 python3 -m pytest -q tests/test_native_replay_storage.py tests/test_resources.py tests/conformance_record_test.py --runtime-root RUNTIME`:
  23 passed in 1.69 seconds. New child commands have 5- or 20-second bounds.
- `timeout 60 python3 -m pytest -q tests/conformance_freeze_test.py tests/conformance_readonly_workload_test.py --runtime-root RUNTIME`:
  30 passed in 2.68 seconds. Existing freezer and read-only behavior passed.
- `timeout 900 nix-build build-support/default.nix -A tests.upstream --out-link build/nix-upstream --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'`:
  58 passed in 1.88 seconds, with no skips. Immutable JUnit evidence:
  `/nix/store/jjjh0n7yjqis8206xlfr198gm132m0hh-sqlite-verifier-test-upstream-1/junit.xml`.
- Independent review and the new Linux paired/full execution evidence remain
  pending. The historical timeout receipts and ext4 sample are unchanged.
