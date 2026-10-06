# One SQL executor implementation status

Created 2026-10-06. Status: IN PROGRESS.
Task: [observable outcomes](20261006-single-sql-executor.task.md).
Sources: public issues #21 and #13.

## Current state

Investigation and task specification are complete. No executable source has
changed. This workspace starts from reviewed support integration `ef2cc19e`,
which supplies the required documentation and replacement rules. Runtime
upgrade acceptance is tracked separately in PR #43.

Relevant definitions and callers are listed in the task file. The removed
executor's unconditional preservation law relied on treating data statements
as errors. Its replacement must state a schema-extension domain explicitly.
The generated starting-schema pattern already exists in the Atuin example.

## Progress

- 2026-10-06: Read both current public issues and confirmed their lack of
  additional comments. Audited execution, bridge, contract and preservation
  definitions and all caller names. Recorded outcomes and verification before
  substantial implementation. The approved small-example baseline currently
  binds two modules and omits its schema SQL; this is the exact intended change.

Final owner review, ordinary and full checks, installed examples and issue
closure remain open. The task is not DONE.
