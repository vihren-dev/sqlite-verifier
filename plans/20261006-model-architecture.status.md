# Status: SQLite model boundary and execution architecture

Created 2026-10-06. Status: DONE on 2026-10-07.
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
- Namespace amendment `bac76f40f3f9d4ed11abb247fe4f9d5db053bb46` passed
  independent review `20261007T073445Z-bac76f40` with no findings. Integrated the
  normally merged, reviewed Lean upgrade main
  `bc9e2dce58f755b608cf00e545162257b81ab51a`. Only the journal conflicted.
  Its 71 main rows and 61 accepted-task rows are retained as 75 distinct rows,
  with both complete parent orders preserved. Main source is unchanged.
- Integration `cd5af3d9be05efd96b173984732017c5f48608f7` passed independent
  review `20261007T073851Z-cd5af3d9` with no findings. A separate read-only
  adversarial audit found no namespace overconstraint: the parent initializer
  rule leaves the leaf choice open, and the initial source directory rule does
  not restrict other distributions' namespace portions. Temporary fixtures do
  not claim implementation or full packaging validation.
- All 16 local references still resolve after the reviewed-main merge. The PR
  diff contains exactly the ADR, its task/status files and the append-only
  journal. Validation receipt: `build/t09-reviewed-main-integration-validation.json`.
  This checkpoint is ready for the authorized task-branch push and PR44 metadata
  update. Final repository delivery remains pending; this task is IN PROGRESS.
  No code/package scaffold, T10 start or other branch change is included.
- The published readiness head
  `9458fc52d7d79f4b003e4535f77cf002eb43c7c2` passed independent Claude review
  `20261007T074454Z-9458fc52` with no findings. Its final exact raw review row
  remains pending and byte-unchanged outside this plans-only closeout commit.
- PR44 was normally merged on 2026-10-07 at 08:03:17 UTC as
  `b91e5cb5b3e145bc9713cc5e2b88bd502aa9ad0a`, delivering the accepted ADR and
  its namespace amendment. The delivered decision uses `Belay.Sqlite` and
  `belay.sqlite`; the Python parent has no initializer and only its `sqlite/`
  child initially. The Lean package boundary and existing CLI names are retained.
  T09 is DONE. Issues #23 and #31 remain open for their implementation work.

## Delivery evidence

[PR44](https://github.com/vihren-dev/sqlite-verifier/pull/44) records exact head
`9458fc52d7d79f4b003e4535f77cf002eb43c7c2` and the normal merge above. All six
check records completed on that head:

| Check | Exact job | Result |
| --- | --- | --- |
| Native Linux CI | [112687010262](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37589402854/job/112687010262) | Success |
| Native Darwin CI | [112687010509](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37589402854/job/112687010509) | Success |
| Protected approved baseline | [112687002597](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37589400426/job/112687002597) | Success |
| Protected approved baseline | [112687154521](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37589448416/job/112687154521) | Success |
| Protected approved baseline | [112687236998](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37589473664/job/112687236998) | Success |
| Release publication | [112692345849](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37589402854/job/112692345849) | Skipped on the PR; no release claimed |

The coordinator retained the raw check response at
`/private/tmp/pr44-9458-check-runs.json`, SHA-256
`56a4206e38b7bcfce1d4378c2c88082f044d3a3f5d3c82e7f383b9baa8201ddf`.
The summary above preserves the exact head, results and public job references
in this plan record; the temporary raw response is not a permanent repository
artifact. Earlier local namespace fixtures remain limited to that contract.

T10 planning commit `2c61f0414407d89f9f984a7d65fd6a69d6083283` remains unchanged.
T10 implementation acceptance has not run, and its code stays held for PR47
and PR48 repository delivery. This closeout changes only T09's task and status;
the feature bookmark, source and review journal remain unchanged. Its planning
references and evidence checks pass under a 15-second bound. Plans-only commits
are exempt from independent review under the repository instructions.
