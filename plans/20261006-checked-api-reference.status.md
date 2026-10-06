# Checked API documentation and reference status

Status: IN PROGRESS. Created 2026-10-06.

Task: [checked API reference](20261006-checked-api-reference.task.md).
Source: [issue #26](https://github.com/vihren-dev/sqlite-verifier/issues/26).
Rules: [AGENTS.md](../AGENTS.md).

Relevant sources: `SqliteVerifier.lean`, `SqliteVerifier/*.lean`,
`lakefile.toml`, `build-support/default.nix`, `build-support/sources.nix`,
`.github/workflows/ci.yml`, `README.md` and CLI argument definitions.

## Progress

- 2026-10-06: Reused the idle maintenance Jujutsu workspace. Its base merges
  the checked Lean upgrade `6917e3c8` with merged main `e9fd9533`, which supplies
  the documentation rules and catalog correction. Preserved every original
  raw review entry from main, the upgrade and the maintenance integration.
- 2026-10-06: Verified the upstream doc-gen4 `v4.34.1` tag directly through
  GitHub's Git-reference API. It resolves to
  `953c8992d174b4e56955e01e101d46668c68f2bb`; an exact matching tag is available.
  The older `v4.34.0` manifest confirms that doc-gen4 has separately pinned
  Lake dependencies and a native SQLite binding. The matching tag's actual
  manifest and native build inputs must be inspected before implementation.
- 2026-10-06: Identified 188 top-level declarations in the current public
  library modules, before counting fields and constructors. Prepared the
  observable task and negative documentation checks before code changes.
  No reference implementation or public docstring change has started.
- 2026-10-06: The matching `v4.34.1` manifest has the same five dependency
  revisions as `v4.34.0`, and its toolchain file selects Lean 4.34.1. Fetched
  and hashed all six exact public sources; local receipts are in
  `build/docgen-source-pins.json`. MD4Lean, UnicodeBasic and leansqlite compile
  bundled native C sources. No SQLite execution-profile version changes.
- 2026-10-06: The combined baseline passes the ordinary command
  `nix develop path:./nix --command timeout 1200 just test`: 328 source tests
  and 28 subtests, plus all six development Nix targets. The complete log is
  `build/t18b-base-integration-check.log`. No executable or formula was changed
  by this baseline merge. Packaging will use doc-gen4's explicit `single` and
  `fromDb` interface, which can avoid its Git-dependent source-URI facets.

## Acceptance remaining

Dependency closure and sandboxed reference build; complete checked public
documentation and proposition restatements; compiling walkthrough; negative
Verso fixtures; README and CLI help links; CI output and both platform checks;
independent reviews. The upgraded runtime's final owner review remains open.
