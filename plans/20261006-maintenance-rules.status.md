# Status: maintenance rules and the default execution profile

Created 2026-10-06. Status: DONE.
Task: [task](20261006-maintenance-rules.task.md).
Sources: public issues #22 and #25.
Relevant files: `AGENTS.md`, `migration_check/profiles.py`,
`migration_check/sql_model.py`, `tests/test_profiles.py`.

## Progress

- 2026-10-06: read the public issues, repository instructions and review
  checklist. Created the task and status files before implementation.
- Remaining cleanup is owned by [#21](https://github.com/vihren-dev/sqlite-verifier/issues/21)
  for `Statement.isExtension`, `run`, `runFrom`, `Executes`, their bridges and
  executor markers; [#15](https://github.com/vihren-dev/sqlite-verifier/issues/15)
  owns the schema lookup cleanup and its marker.
- Issue #22 can close after this task passes because the remaining cleanup is
  tracked. Issue #25 remains open until the actual Lean upgrade in #24 passes.
- 2026-10-06: added the exact replacement rule and stable-Lean policy to
  `AGENTS.md`; renamed the default profile and all callers without an alias.
  The policy excludes release candidates and SQLite profile versions.
- 2026-10-06: checks passed in `nix develop path:./nix`: 112 tests across
  `tests/test_profiles.py`, `tests/test_cli_inputs.py`, `tests/test_translation.py`,
  `tests/test_schema_translation.py`, `tests/test_sql_writes.py` and
  `tests/schema_generation_test.py`, in 7.17 seconds, under a 60-second limit.
  Used the existing runtime at
  `/nix/store/w9kdpy4l8aa31bjdy924iw23lzq6czhi-sqlite-verifier-runtime-1`.
  Source search found the new name at all three caller files and no old constant.
- 2026-10-06: Claude independently reviewed implementation commit `04122dc3`
  through `REVIEWER=claude just review`: no must or should findings, exit 0.
  The append-only review record is `20261006T083403Z-04122dc3`. DONE.
