# Application-key acceptance on delivered main

Audience: team and reviewers. Recorded 2026-10-07.

Reviewed head `f3ea1d44` integrates delivered main `eb061e76`. All 16 feature
files and 106 accepted runtime inputs retain their original digests. Actual
Nix evaluation returns the accepted runtime. The original fresh offline
archive and installed acceptance remain bound to that unchanged runtime.

[Linux CI](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37647223426)
passes all nine Nix suites, with 503 tests passing. Source checks pass 369 tests
and 35 subtests, with two existing optional reviewer-tool skips. Counts are
from the original decoded console log. The gzip file retains its exact UTF-8
bytes; [the receipt](linux.json) records their hash. Hosted XML remains in the
workflow artifacts. The macOS PR job skips execution and is not a native pass.

The current local macOS Nix evaluation returns seven successful cached ordinary
suite outputs, with 307 passing tests and no failures, errors or skips.
[The original output bindings](ordinary.json) and seven XML files retain the
original timestamps and node identities. This evaluation does not claim fresh
execution. No failed historical record is relabeled.

The 42 current integration checks and 35 subtests pass. Their original XML,
feature digests, runtime input digests and journal preservation checks are
retained here. All three parent journals remain ordered subsequences, including
repeated rows. Independent review of the integration has no findings.

Final owner review and normal delivery remain required.
