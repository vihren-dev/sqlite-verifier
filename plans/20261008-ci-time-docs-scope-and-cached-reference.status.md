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
- 2026-10-08: commit `b1363a62`, refactor review
  `20261008T131057Z-b1363a62` with no findings. Both findings of the first
  review are recorded as fixed.
- 2026-10-08: the reference is two Nix targets. `apiReferenceBase` builds the
  pages and all checks with the placeholder `SOURCE-REVISION`; it takes no
  commit. `apiReference` copies it and puts the commit into the source links
  (`tools/api_reference_links.py`). `tools/ci_store_gc.py` roots the base.
  Local measurement on macOS arm64, with the sandbox:

  | Build | Time | Built derivations |
  | --- | --- | --- |
  | `apiReference` for `b1363a62` | 403 s | base and link step |
  | `apiReference` for `318b7fdb` | 1.9 s | link step only |

  Both outputs have 279 source links with their commit and no placeholder.
  They differ in 25 files: the pages with source links and the report. The
  base output is 172 MB, 7.7 MB with zstd level 3. Rooting the base keeps its
  build inputs, including doc-gen4, which is 194 MB, 45 MB compressed. No
  previous CI root contained doc-gen4, so CI also rebuilt it in each
  non-documentation run. The saved cache grows by about 53 MB for each
  platform. 56 focused tests pass.
