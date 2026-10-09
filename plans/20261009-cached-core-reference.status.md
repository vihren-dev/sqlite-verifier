# Status: cached core API reference without checks of doc-gen4

Created 2026-10-09. Status: IN PROGRESS.
Task: [task](20261009-cached-core-reference.task.md).
ADR: [ADR 0009](../docs/adr-0009-cached-core-reference.md).

Relevant files: `build-support/api-reference-core.nix`,
`build-support/api-reference.nix`, `build-support/default.nix`,
`tools/api_reference.py`, `tools/api_reference_links.py`,
`tests/test_api_reference.py`, `tools/ci_store_gc.py`,
`tests/test_ci_store_gc.py`, `docs/api-reference.md`, `docs/ci.md`,
`build-support/README.md`.

## Progress

- 2026-10-09: ADR 0009 accepted and merged in PR #65. Task and status files
  created. PR #65, a documentation-only change, took 8 s and 11 s on Linux CI,
  against 8.5 minutes for PR #61 before PR #63.
