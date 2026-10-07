# Native Linux acceptance for the model package

Created 2026-10-07. Audience: team and reviewers.
Task: [T10](../../plans/20261007-model-package-and-frontend.task.md).

GitHub CI run `37655729129`, Linux job `112910873523`, checks published
head `71d561ae`. The complete package scope runs every suite, host source
and Nix infrastructure checks, and fresh offline archive acceptance.

All nine Nix suites pass 509 checks, with no failures, errors or skips.
Nix infrastructure passes 102 checks. Fresh installed package and Atuin
acceptance passes 26 checks, including the new model and codec consumer
and independent frontend import. The source XML records 371 passing
tests, 37 passing subtests and two optional reviewer-tool skips. The
receipt names those skipped nodes and their original reasons. No skip
is counted as passing.

`case-reports.zip` retains the exact GitHub artifact bytes. Its SHA-256
matches the workflow artifact digest. Original XML and phase records are
also retained individually; the receipt maps each file to its original
ZIP member and binds its bytes. The native runtime archive remains in
GitHub artifact `11499372088`, with its size, digest and expiry recorded.
The complete Linux job succeeds, including cache retention and all artifact
uploads. All recorded phase exit codes are zero. The macOS PR job skips execution; separate actual native
macOS evidence supplies that platform's acceptance. Final owner review
and normal repository delivery remain required.
