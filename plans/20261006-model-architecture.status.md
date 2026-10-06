# Status: SQLite model boundary and execution architecture

Created 2026-10-06. Status: IN PROGRESS.
Task: [task](20261006-model-architecture.task.md).
Sources: public issues #23 and #31, including #23's boundary comment.
Relevant files: `lakefile.toml`, `SqliteVerifier.lean`,
`SqliteVerifier/Model.lean`, `SqliteVerifier/SqlExecution.lean`,
`StructuralCodec.lean`, `build-support/{sources,default,runtime}.nix`,
`migration_check/{runtime,source_closure,prepare,bundle,sql_model,structural}.py`.

## Progress

- 2026-10-06: created an isolated Jujutsu workspace from main commit
  `4a4258283590273b142bbd6b6bdab202e2ee4038`. Read the public issues,
  applicable instructions, review checklist and current boundary code.
- 2026-10-06: task and status files created before the ADR. Confirmed that
  schema lookup is used by core conformance and must remain model-owned during
  the package split. Owner acceptance is required before dependent changes.
