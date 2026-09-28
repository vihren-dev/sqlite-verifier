# Nix-only parser builds

Created: 2026-09-28. Status: DONE.

`just parser` must build both pinned SQLite parsers through Nix and retain the
existing `build/` executable and grammar paths. Nix owns build reuse; remove the
Python build orchestrator and its environment/content-stamp cache.

Keep grammar transformation, upstream checksum verification and token-inventory
agreement checks. Parser recognition, malformed-input, byte-span, release and
translation behavior must remain unchanged. Existing immutable runtime packaging
must still consume the parser output. Replace obsolete cache tests with a small
generator regression and update the reviewed unit and scenario inventories.

Validate the real Nix build and repeat-build reuse, parser/translation suites,
generator failure checks, resource-free collection and cached unit checks.
Relevant files: `build-support/default.nix`, `parser/generate.py`, `justfile`,
`tests/parser_build_test.py`, `build-support/unit-cases.json`.
