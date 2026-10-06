# Optional upstream catalog tests

Status: IN PROGRESS. Created 2026-10-06.

## Outcome

Direct pytest runs of `tests/conformance_catalog_test.py` skip its three
archive-dependent cases when `CONFORMANCE_UPSTREAM` is absent. The skip message
identifies the missing variable and the pinned Nix upstream target that supplies
it. An explicitly configured empty, invalid or changed archive causes failure.
Pure catalog checks and unrelated tests remain runnable.

The Nix upstream suite continues to execute all three catalog cases. Its
assertions retain the 171-file catalog, representative feature families, file
exclusion reasons and refusal of missing or extra family members.

Source: [issue #38](https://github.com/vihren-dev/sqlite-verifier/issues/38).

## Acceptance

A bounded subprocess regression invokes the actual catalog tests with the
variable absent and confirms successful exit, three skips and an actionable
message. Explicit empty and invalid paths fail with no skips. A changed
archive's missing or extra family member fails with no skips.

A bounded run with the pinned archive executes and passes all three original
catalog cases. The pure source-catalog tests remain runnable without the
archive. Each subprocess has a short timeout. The Nix upstream suite retains
its archive environment and catalog test ownership.

## Constraints

The shared `upstream` fixture in `tests/conformance_catalog_test.py` supplies
the archive to all three cases. Absence means that the variable is unset; a
configured path must never become an optional-prerequisite skip.
`conformance/upstream_catalog.py:validate_source_files` owns family validation.
`build-support/tests.nix` supplies the pinned archive and
`tests/nix_suites.json` selects the catalog module for the upstream suite.
No corpus or catalog membership changes belong to this fix.
