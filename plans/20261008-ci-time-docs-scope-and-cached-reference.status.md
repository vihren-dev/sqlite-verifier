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
