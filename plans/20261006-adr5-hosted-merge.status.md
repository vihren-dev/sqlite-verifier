# ADR 0005 hosted validation and merge status

Created 2026-10-06. Status: DONE, verified 2026-10-06.
Task: [hosted validation and merge](20261006-adr5-hosted-merge.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

[PR #32](https://github.com/vihren-dev/sqlite-verifier/pull/32) merged after
successful hosted CI on ubuntu-22.04 and macos-14 and the protected-baseline
check, at the exact approved head. All six requested post-merge issues exist.
The ADR records the owner's decision to retain the independent SQLite 3.53.4
native pin. The sample remains 184 cases with its 60-second phase limit;
no test retries or deadline changes were needed. The
[validation record](20261006-adr5-hosted-validation.md) links actual jobs,
verification results and follow-up issues. This task is DONE.

## Progress

- 2026-10-06: Read the owner review, existing CI routes, completed v5 evidence
  and workspace process. Prepared this task/status pair before publication or
  any necessary hosted correction. Read-only checks inspect CI scope and draft
  the six requested follow-up issues. No retries or semantic changes are planned.

- 2026-10-06: Recorded the owner's decision to retain the independent 3.53.4
  native pin, while keeping the production proof and model scope separate.
  Markdown links pass. Existing CI selects the complete packaging route on both
  approved hosted runners, including the v5 sample and full model target. The
  branch has no existing PR, and no open issue duplicates the six requested
  follow-ups. Main remains `31848aac`; the existing branch-start commit
  `2839c93c` is empty and has no description. Publication retains its original
  identity rather than rewriting source-bound evidence.

- 2026-10-06: Published `f22b6573` as `adr5/reference-corpus` and opened
  [PR #32](https://github.com/vihren-dev/sqlite-verifier/pull/32). Its protected
  baseline check passed; both native jobs started the complete packaging route.
  The active main ruleset requires an up-to-date branch and all three checks.
  Integrated main `31848aac` with a merge commit, preserving the original
  source/evidence commits. Markdown links pass; hosted CI will validate this
  new merge candidate. The earlier run remains visible as superseded evidence.

- 2026-10-06: Both platform jobs passed the complete package route at
  `fea719a0`, and protected-baseline checks passed. Inspected actual job logs,
  phase records and raw JUnit: full model 322 plus the expected Tcl skip,
  actual upstream 58, sample 12, source 286 plus 28 subtests, Nix 68 and
  installed runtime 21 pass on both platforms. Sample assertions establish
  the unchanged child/phase bound; JUnit includes extra validation time and
  does not supply an exact CLI phase value. Verified the 52-file evidence
  inventory. Confirmed clean merge readiness and merged without overriding
  branch protection, producing `98e81799`. Created issues #33–#38 after the
  merge with source-backed outcomes and verification requirements. Frozen
  evidence and semantic-model scope remain unchanged. Markdown and CI routing
  checks pass; marked task/status DONE.
