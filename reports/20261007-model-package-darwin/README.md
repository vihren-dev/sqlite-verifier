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

`source-corrected.xml` and `identities.xml` record the earlier checked model
integration `e38bc101`: 373 source checks with 37 subtests, and 93 Nix identity
checks. `review-correction.xml` records 19 checks after the comment correction
in `380c9de2`. These files retain their original dates. The final nine-suite
Nix run is still in progress. Linux acceptance and final owner review remain
required. This report does not mark T10 complete.
