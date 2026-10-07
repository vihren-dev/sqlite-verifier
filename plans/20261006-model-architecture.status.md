# Status: SQLite model boundary and execution architecture

Created 2026-10-06. Status: IN PROGRESS; accepted decision delivery is pending.
Task: [task](20261006-model-architecture.task.md).
ADR: [accepted decision](../docs/adr-0006-model-boundary-and-execution-levels.md).
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
- 2026-10-06: drafted ADR 0006 with separate model and codec libraries, a
  structural Python frontend, exhaustive statement categories, shared atomicity
  and constraint checks, and script-owned positions. Recorded the actual
  `ProfileExecutes` relation and pending visible/persisted outcomes to preserve.
- 2026-10-06: traced Nix source staging, root-only library installation,
  runtime lookup, source dependency resolution and bundle trusted imports.
  The proposed layout includes both installed package outputs and exact module
  origins. Model lookup and projection facts remain available without the
  contract; table shapes and future SQL support remain separate work.
- 2026-10-06: bounded local-link validation passed for all 12 ADR links.
  No executable source changed. No future implementation check is claimed as
  executed. Independent review and final owner acceptance remain.
- 2026-10-06: Claude independently reviewed ADR commit `996cc60e` through
  `REVIEWER=claude just review`: no must or should findings, exit 0.
  Review record: `20261006T092414Z-996cc60e`. The ADR is ready for final owner
  acceptance. It remains PROPOSED; dependent package/execution changes wait
  for that acceptance. This task is not DONE.
- 2026-10-07: The owner accepted PR44 with the Python import/layout amendment
  `belay.sqlite`, a `belay/` namespace directory without `__init__.py`, and only
  its `sqlite/` child initially. Package/execution implementation remains gated
  and unstarted; this task resumes only the accepted ADR and delivery update.
- Integrated reviewed main `6852f6fac316b2f5c177d561ba924e7c73640f9e` using a
  merge. Only the review journal conflicted. Preserved its 57 main rows and
  11 task rows as 59 distinct rows, retaining each complete parent order.
  The diff against main contains only this ADR, its task/status and the journal.
  Every main source file is unchanged. The accepted namespace amendment and
  final delivery remain to be recorded; this task is IN PROGRESS.
- Merge `e60265ded44004ecbe7a461f1cb13ae45157203f` passed independent Claude
  review `20261007T072909Z-e60265de` with no findings. The exact new row is
  preserved with the next checked ADR amendment.
- Recorded the owner-accepted date 2026-10-07 in ADR0006. The Python frontend
  import package is `belay.sqlite`; `belay/` is a namespace directory without
  `__init__.py` and has exactly its `sqlite/` child at the initial split. Lean
  `Belay.Sqlite`, its Lake package boundary, existing CLI/distribution names and
  implementation gates are unchanged. No package scaffold or T10 work starts.
- All 16 actual local references resolve. Two isolated Python 3.14.7 namespace
  import witnesses accept the parent layout with either leaf initializer choice;
  three prohibited parent layouts are refused. These are temporary name/layout
  fixtures, not frontend implementation or package-boundary acceptance. The
  check has a 15-second bound. Receipt:
  `build/t09-accepted-namespace-bounded-validation.json`. The repository has no
  new `belay/` or `packages/belay-sqlite/` tree. Delivery and final integration
  with the newly reviewed main remain pending.
