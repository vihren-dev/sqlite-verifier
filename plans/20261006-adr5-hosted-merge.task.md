# ADR 0005: hosted validation and merge

Created 2026-10-06. Status: IN PROGRESS.
Status: [progress](20261006-adr5-hosted-merge.status.md).
Specs: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md),
[completed review repair](20261002-adr5-review-remediation.status.md).
Owner instruction, 2026-10-06: publish the approved branch and open a PR;
merge only after CI passes on ubuntu-22.04 and macos-14. Do not add retries.

## Observable outcomes

The approved ADR 0005 work is published in a PR against main. The exact candidate
that merges has successful hosted checks on ubuntu-22.04 and macos-14, including
the v5 development sample. Existing protected-baseline checks pass. The ADR
records the owner's decision to retain the independent SQLite 3.53.4 native pin;
this decision does not extend the production proof profile or semantic model.

A failed hosted sample receives a focused correction to sample size or its
configured deadline, with the measured reason documented. Failed runs remain
visible. No retries are added, and frozen corpus and historical evidence bytes
remain unchanged. Successful CI is bound to the actual PR head and job URLs.

After merging, GitHub issues track development replay headroom, verified foreign-
key reset points, faithful date/precision acquisition, authored immediate-mode
transaction groups, Linux ext4 replay cost and explicit tmpfs setup, and the
catalog test's outside-Nix skip. Existing matching issues are reused where useful.

## Verification and constraints

Hosted job conclusions, step results and retained reports establish both native
platform checks. Current local checks cover any changed code; Markdown links
are checked for documentation changes. Commands have configured deadlines.
The existing 56.6-second Linux sample against a 60-second limit leaves little
headroom. The ADR requires every authored case and the synthetic workload in the
development tier; the remaining upstream sample can be bounded. Full checks and
unsupported model verdicts retain their meanings.

Relevant sources are `.github/workflows/ci.yml`, `tests/ci_scope.py`,
`tools/ci_checks.py`, `build-support/tests.nix`, `conformance/replay_tiers.py`,
and `tests/conformance_catalog_test.py`. Current execution evidence remains
bound to its original source revision and must not be relabeled after changes.
