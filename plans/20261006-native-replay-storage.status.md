# Full native replay storage status

Status: DONE. Created and completed 2026-10-06.

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
  review is complete. Historical timeout receipts and the ext4 sample are
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
  measurement helper and retained evidence is complete, with the documented
  historical-helper recommendations deferred.
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
- Corrected packet `eb7141f9` passed its documented verifier in a clean
  tracked-file snapshot at
  `/private/tmp/sqlite-verifier-storage-clean-o37t3s_q`; no untracked report was
  needed. Its review had no must findings and two should findings. Fixed the
  report-digest message and added a bounded regression that changes the raw
  report, rebinds its gzip inventory and verifies rejection by the original
  execution receipt. The unmodified evidence verifier still passes.
- Final correction `062a9792` passed Claude review with no findings
  (`20261006T130430Z-062a9792`). All must findings are fixed. The tamper
  regression passed in 0.81 seconds; the unmodified verifier checked all 4,376
  identities and all three paired cases again. Jujutsu diff against `4a425828`
  is empty for frozen corpora v1–v5 and the historical execution directory.
  All task acceptance outcomes are complete. The final append-only review
  entry remains pending for the next integration commit.
- 2026-10-06: Ordinary integration exposed a test ownership defect: the
  source suite supplied the verification runtime, but full native receipt
  checks need the conformance runner. Assigned the storage tests to the
  existing upstream Nix suite, which supplies the conformance runtime, and
  declared its freezer fixture, requirement inventory, historical corpora,
  resource helper and native build inputs. The real freezer and full CLI
  checks remain enabled; no prerequisite check or assertion was removed.
- 2026-10-06: Integrated merged main `e9fd9533` and preserved every exact
  review line from both branches. The corrected ordinary command,
  `nix develop path:./nix --command timeout 1200 just test`, exits 0.
  All six development Nix targets pass, including 71 upstream and storage
  checks in 5.01 seconds. Source JUnit and the complete command log are
  `build/test-results/source.xml` and `build/t04b-integration-check.log`.
  The recorded full Linux diagnosis remains bound to its original source
  snapshot; this correction changes test ownership and declared Nix inputs.
- 2026-10-06: Hosted PR #46 validation exposed a deterministic synthetic-fixture
  defect on both platforms. `source_tree` omitted the `tools` package even
  though storage/freezer tests require `tools/__init__.py` as a declared Nix
  input. All dependency-identity cases therefore failed before evaluating
  their intended mutation. This is repository-owned fixture wiring.
- 2026-10-06: Merged verified main `ba48d848`, including foreign-key acquisition.
  Combined both branches' upstream test ownership and preserved all exact
  review-journal rows and their order, including the pending `dd80a0ae` review.
  The source fixture now copies the required package. Extended actual Nix
  derivation-identity checks for every new storage/freezer input, corrected
  historical-corpus target ownership, and covered both new upstream test files.
  No declared input, prerequisite, assertion or timeout was removed.
- 2026-10-06: Rechecked the complete ordinary Nix infrastructure selection
  after the fixture correction: 80 passed in 90.82 seconds, including 37 real
  dependency-invalidation mutations. The new cases cover the required package
  marker, resource helper, freezer fixture, requirement inventory, all retained
  corpus versions, native build pins and both new upstream-owned test files.
  The existing 600-second command and per-child bounds remain unchanged.
- 2026-10-06: Rebuilt the actual isolated upstream target after merging
  `ba48d848`: 76 passed in 4.46 seconds with no skips, failures or errors.
  This includes all previous 71 storage/upstream checks and five merged
  foreign-key recovery cases. JUnit is retained at
  `/nix/store/m3ihx07w4rdig5kx95y9pa045z80n2gf-sqlite-verifier-test-upstream-1/junit.xml`;
  the infrastructure JUnit is `build/test-results/t04b-nix-fixture.xml`.
  No full-model, acquisition-yield or performance run was needed for this
  repository-owned fixture correction. Independent review is pending.
- 2026-10-06: Fixture correction and main integration `e757275e` passed
  Claude review with no findings. The checked tip is ready for the PR #46
  update; no push or PR merge was performed here. The new review-journal
  entry remains pending for the next integration commit.
