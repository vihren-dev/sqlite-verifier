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
- 2026-10-06: Claude review of `cf763a7d` completed with no must findings and
  five should findings (`20261006T091957Z-cf763a7d#1`–`#5`). Fixed all five:
  removed duplicated capacity text, shared the default native engine and
  executable-selection policy, clarified the receipt-path message, added real
  freezer CLI checks and supplied the missing test-variable type annotation.
- 2026-10-06: The coordinator confirmed that the Linux host is idle. New
  paired and full measurements will start after the correction review passes.
  The retained toolchain-validation directory remains outside this task.
- 2026-10-06: Claude review of correction `9d024378` completed with no must
  findings and two should findings. Fixed the receipt-path wording
  (`20261006T092610Z-9d024378#2`). Rejected the proposed valid-CLI skip/mock
  (`#1`): the development environment requires 10 GiB free, and workspace
  instructions require reporting an insufficient-resource prerequisite rather
  than hiding it in a successful test. Both outcomes are logged.
- 2026-10-06: The coordinator reported a separate hosted Darwin full-model
  Nix builder timeout at 600 seconds on existing main. This task's native
  command remains bounded at 420 seconds. Its native phase, full command and
  the development sample are separate measurements; no bound or frozen
  denominator has been changed to resolve that full-suite failure.
- 2026-10-06: Review of `a15be3c5` had no must findings and one should finding
  (`20261006T093348Z-a15be3c5#1`). Split the missing-root and misplaced-receipt
  diagnostics into separate checks in the operational-report module, with
  tests for both conditions. Both messages now identify the failed input and
  the required correction.
- 2026-10-06: Correction `698cc4d4` passed Claude review with no findings
  (`20261006T093857Z-698cc4d4`). Staged only tracked public source plus the
  measurement helper in a separate Linux directory. Verified that local and
  remote archive hashes match. No retained toolchain evidence was changed.
- 2026-10-06: Completed serial Linux ext4/tmpfs comparisons and one bounded
  full tmpfs replay. Retrieved the receipts and locally checked exact frozen
  observations, complete paired fresh records, profiles, native source ids,
  case names, all actual fixture paths and execution source hashes. Preserved
  historical timeout receipts and the passing ext4 sample.

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
- The new Linux paired/full execution evidence is retained below. Packet
  review remains pending. Historical timeout receipts and the ext4 sample are
  unchanged.
- After review corrections, `timeout 60 python3 -m pytest -q tests/test_native_replay_storage.py tests/test_resources.py tests/conformance_record_test.py tests/conformance_driver_profiles_test.py --runtime-root RUNTIME`:
  44 passed in 2.78 seconds, including alternate pinned engines and the actual
  freezer CLI's required root, invalid-root refusal and derived receipt path.
  The freezer subprocess has a 30-second timeout.
- Rechecked the same 44 cases after the diagnostic split; all passed. The
  new Linux measurement helper is prepared locally, but no remote timing has
  started yet.
- Linux execution is retained in
  [the storage evidence record](../reports/20261006-native-replay-storage/README.md).
  Three paired cases passed exact fresh/frozen and cross-storage equality.
  Trigger-prefix native timings were 10.7872 seconds on ext4 and 0.0853 seconds
  on tmpfs. Each child kept its 60-second bound.
- The actual full v5 corpus CLI completed in 91.1252 seconds under its
  unchanged 420-second bound. The native phase took 42.5182 seconds and passed
  all 4,376 frozen comparisons. All 4,376 ordinary-file paths were audited
  under the declared tmpfs root; all before/after bindings match. Model
  classification remains 4,376 `MODEL_UNSUPPORTED`.
- Linux host compute was released after the completed run. Review of the
  measurement helper and retained evidence remains pending.
- `timeout 30 python3 reports/20261006-native-replay-storage/validate.py`:
  verified all 4,376 full-run identities, native completion/path bindings,
  all three paired fresh/frozen comparisons, recorded phase bounds, byte
  inventory and original execution source hashes. The verifier can be rerun
  against the recorded original source revision. The measurement helper's
  retained hash matches its actually executed bytes.
- 2026-10-06: Jujutsu's default 1 MiB new-file guard refused the 2.1 MiB
  full report while committing the execution packet. Retained it as
  deterministic `full.json.gz`, verified exact decompression and the recorded
  raw report digest, and updated the verifier and inventory. No Jujutsu
  configuration, native observation, profile or frozen corpus was changed.
- Packet review `20261006T124913Z-452e432c` reported two must findings for the
  missing large report and eight should findings. The gzip packaging and clean
  snapshot validation fix the must findings. Updated verifier diagnostics and
  status wording. The five recommendations about the measurement helper are
  deferred: it is the exact executed historical helper whose byte hash binds
  this run. Its actual bounded Linux execution and retained comparisons passed;
  a future measurement revision can add policy tests and improved messages
  without changing this executed evidence.
