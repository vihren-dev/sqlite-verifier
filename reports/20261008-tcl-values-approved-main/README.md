# T17 acceptance after approved main integration

Integrated the approved feature head `488e7829` with accepted main
`1198867a`, which includes PRs #57 and #53. The owner approves PR #50,
subject to passing checks and normal merge.

The complete macOS command exited successfully:

```sh
nix develop path:./nix --command timeout 2400 just test-full test-nix
```

The nine native suites pass 558 tests with no failures, errors or skips.
The source checks pass 412 tests and 35 subtests. The infrastructure
checks pass 98 tests. `receipts.json` records each suite's output path,
test count and original timestamp. Cached outputs keep their original
timestamps; these results do not imply that every builder ran again.
The retry rebuilt harness, model, sample and upstream. The frozen suite
completed in the first attempt and was reused by the retry.

The first attempt failed during harness collection. A transaction test
added on main imported `decode_rows` from its old module. The test now
imports it from `conformance.native_bindings`. The original failed log
and successful retry log are retained separately.

`current-source.json` binds the feature files and integration changes.
The original source comparison predates the transaction-test import fix.
Original parent journals and their preservation check retain all rows,
including repeated rows, in their original order. Compressed JUnit files
retain the original bytes. `sha256.json` binds the retained artifacts.

Fresh hosted Linux checks and normal merge are pending. Issue #35 remains
open: the fixed date cohort is partial coverage of the upstream family.
