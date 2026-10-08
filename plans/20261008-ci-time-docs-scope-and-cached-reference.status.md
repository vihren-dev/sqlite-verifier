# Status: short CI for documentation changes and a reusable API reference

Created 2026-10-08. Status: IN PROGRESS.
Task: [task](20261008-ci-time-docs-scope-and-cached-reference.task.md).
Owner decision: option A, a cacheable reference build on every pull request
(2026-10-08).

Relevant files: `tests/ci_scope.py`, `tests/test_ci_scope.py`,
`tools/review_log.py`, `.github/workflows/ci.yml`,
`build-support/api-reference.nix`, `build-support/default.nix`,
`tools/api_reference.py`, `tests/test_api_reference.py`,
`tools/ci_store_gc.py`, `justfile`.

## Findings

- PR #61, run `37775712781`, Linux job `113305887800`: scope `test` for three
  changed paths (two ADRs and `reviews/log.jsonl`). Steps: cache restore 92 s,
  API reference 235 s, checks 160 s.
- The reference derivation takes `github.sha` as `revision`, so Nix cannot
  reuse it between commits.
- `tools/ci_store_gc.py` does not root the reference, so the saved cache would
  not contain it even without the revision.

## Progress

- 2026-10-08: task and status files created.
- 2026-10-08: commit `318b7fdb`. The review log joins documentation in the
  `docs` scope (`tests/ci_scope.py::RECORD_FILES`). `tools/review_log_check.py`
  checks the log in every scope. A first rule that required the base lines in
  order failed on 6 of the 267 parent and child pairs of main's history. All 6
  are merges of main into a task branch; they reordered lines and lost none.
  The rule therefore requires presence only; all 267 pairs pass it.
- 2026-10-08: review `20261008T130640Z-318b7fdb` found that the review
  statistics took the last line as a finding's latest outcome, which a reorder
  can change (R11, must), and that `docs/ci.md` still described a
  Markdown-only `docs` scope (R13, should). The commit also had the old task
  text, because a scripted edit of the plan failed before the commit.
  `latest_outcomes` now uses the resolution date, with the line only for equal
  dates. `docs/ci.md` describes the scope and the log check. The task text
  describes the presence rule.
