# Native macOS acceptance for the model package

Created 2026-10-07. Audience: team and reviewers.
Task: [T10](../../plans/20261007-model-package-and-frontend.task.md).

Implementation `380c9de2` supplies the standalone model package, frontend and
two trusted compiled roots. `receipt.json` binds each Nix component input to
the matching checkout file bytes. It records the immutable runtime, fresh
archive hash and installed content-addressed runtime. The archive remains in
the build directory; it is not committed.

The fresh archive passes all 26 installed package and Atuin checks in
124.695 seconds, with no failures, errors or skips. The command selects
`--runtime-variant installed` and `--runtime-archive`, with no development
runtime root. The existing installer verifies and imports the offline Nix
closure. Installed children use an unrelated directory and poisoned ambient
Python and Lean paths. The neutral consumer and independent frontend import
checks execute against the installed files.

The original installed JUnit file and compressed console log are retained.
`archive.log.gz` records content addressing, closure export and verification.
`final-runtime.log.gz` records the runtime build. The receipt binds each raw
file by SHA-256 and byte count; compressed logs decode to those original bytes.

The final reviewed inputs pass all nine native Nix suites: Atuin 12, bundle
48, CLI 15, frozen 145, harness 122, kernel 28, model 51, sample 12 and
upstream 76. All 509 checks have zero failures, errors or skips. Each
original JUnit file retains its timestamp and selected node identities. The
receipt names the immutable outputs. The complete bundle suite ran before
the other builders under the existing Darwin scheduling rule.

The final source run passes 373 tests and 37 subtests in 44.03 seconds.
The final Nix infrastructure run passes 102 checks in 118.40 seconds. Its
checks include actual isolated model builds and dependency invalidation.
Original XML and console bytes are retained. Earlier checked source and
identity runs remain in `source-corrected.xml` and `identities.xml`; they
are not substituted for these final results. `review-correction.xml`
retains the 19 focused checks after the comment correction.

`baseline-namespace-changes.json` lists the seven changed example source
pins. The namespace change requires new source hashes. Pin sets and raw
SQL pins are unchanged. Owner review remains required for these pins and
the trust changes. Linux acceptance and final owner review are pending;
this report does not mark T10 complete. The completed checks leave local
free space below the required threshold for another expensive run. No
automatic cleanup is performed.
