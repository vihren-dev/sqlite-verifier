# ADR 0005 hosted validation record

Verified 2026-10-06. Audience: the team reviewing merge readiness.
Task: [hosted validation and merge](20261006-adr5-hosted-merge.task.md).

[PR #32](https://github.com/vihren-dev/sqlite-verifier/pull/32) merged after all
three required checks passed. The validated head is
`fea719a0579b2e17bc7af3d00b13869556a295d1`; the merge commit is
`98e81799c96df3eff5c77839fed27a931eb0a1d9`.
The [successful CI run](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37424910370)
used ubuntu-22.04 and macos-14. Actual images were Ubuntu 22.04.5 and macOS
14.8.9 on ARM64. The
[protected-baseline check](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37424906207)
also passed before merge. The branch included the current main revision.

| Check | Linux | macOS |
| --- | --- | --- |
| Full package command | Passed, 737.185 s | Passed, 1,210.086 s |
| Full isolated model | 322 passed, one expected Tcl skip; 307.310 s | 322 passed, one expected Tcl skip; 367.920 s |
| Pinned upstream target | 58 passed, no skips | 58 passed, no skips |
| V5 development sample target | 12 passed, no skips; 102.054 s | 12 passed, no skips; 92.604 s |
| Source checks | 286 tests plus 28 subtests passed | 286 tests plus 28 subtests passed |
| Nix checks | 68 passed | 68 passed |
| Installed runtime checks | 21 passed | 21 passed |

The sample target's JUnit duration includes a second complete corpus load for
membership assertions. It is not the timed replay phase. Passing assertions
establish that the child command and its fresh load/native replay/classification
phase stayed below 60 seconds, with the unchanged 184 selected cases. Exact
hosted phase values were not retained. No sample reduction, deadline increase
or test retry was needed. The actual upstream target covers the model's expected
Tcl omission. Both package commands ran the complete checks.

Actual job logs, phase records and raw JUnit reports were inspected and hashed.
The local verification inventory binds 52 files; its summary SHA256 is
`eb5fe9636f2ed0cf2cc4b5d649bbc9b9c4f09f3fccbedb598d1d7011cd72c4e0`.
Job logs: [Linux](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37424910370/job/112142364988),
[macOS](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37424910370/job/112142365133).
The workflow retains downloadable case-report artifacts for 14 days.

The [initial publication run](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37424615765)
was superseded when current main was merged into the branch to meet its strict
up-to-date rule. It remains visible; no workflow rerun was requested.
Frozen v1–v5 and retained native execution evidence remain unchanged.

## Follow-up issues created after merge

- [#33: development replay headroom](https://github.com/vihren-dev/sqlite-verifier/issues/33).
- [#34: verified foreign-key profile recovery](https://github.com/vihren-dev/sqlite-verifier/issues/34).
- [#35: exact date/REAL and Tcl binding acquisition](https://github.com/vihren-dev/sqlite-verifier/issues/35).
- [#36: authored immediate-mode transaction groups](https://github.com/vihren-dev/sqlite-verifier/issues/36).
- [#37: Linux disk replay cost and explicit tmpfs conditions](https://github.com/vihren-dev/sqlite-verifier/issues/37).
- [#38: outside-Nix catalog test skip](https://github.com/vihren-dev/sqlite-verifier/issues/38).

The owner's decision to retain the independent SQLite 3.53.4 native pin is
recorded in the [ADR](../docs/adr-0005-conformance-corpus-scale.md).
Production model extension and C8 remain subsequent work.
