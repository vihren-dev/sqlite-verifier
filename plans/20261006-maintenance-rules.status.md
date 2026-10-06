# Status: maintenance rules and the default execution profile

Created 2026-10-06. Status: IN PROGRESS.
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
