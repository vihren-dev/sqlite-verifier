# Short CI for documentation changes and a reusable API reference

Created 2026-10-08. Status: IN PROGRESS.

## Outcome

1. **Documentation pull requests get the documentation scope.** A pull request
   that changes only documentation and the review log (`reviews/log.jsonl`)
   gets the `docs` scope: link checks without a build. Today the review log
   makes such a pull request run the `test` scope. PR #61 changed two ADRs and
   the log, and its Linux job ran for 8.5 minutes.
2. **The review log stays append-only.** Every CI run checks that each line of
   the log is a valid review record, and that every line of the base commit is
   still present and unchanged. Merges of main into a branch reorder lines, so
   the review statistics take the latest outcome of a finding by its date, not
   by its line. Nothing checks this rule today.
3. **The API reference is reused when the Lean sources do not change.** The
   expensive reference build (Lean build, doc-gen4 and the link check) does not
   depend on the commit hash. It produces source links with a fixed
   placeholder. A cheap step replaces the placeholder with the checked commit
   hash and checks the source links. On a commit that does not change the Lean
   sources, CI reuses the expensive build from the cache. PR #61 spent 235 s
   in this step.
4. **The reused build survives the CI cache cleanup.** `tools/ci_store_gc.py`
   keeps the revision-free reference build, so the saved cache contains it.

The published reference is the same as before: the same pages, the same source
links with the full commit hash, and the same local-link check. The `docs`
scope still runs the link checks and the CI scope unit tests. All other scopes
are unchanged.

## Tests

- `tests/test_ci_scope.py`: the review log alone, and the review log with
  documentation, give `docs`. The review log with any other file gives the
  scope of that file. Other `.jsonl` files and files under `reviews/` that are
  not the log give `test`.
- A test of the review-log check, with temporary logs: it accepts appended
  lines, lines from a merge between the base lines, and reordered lines. It
  refuses a changed or removed base line, a line that is not a review record,
  and an empty log when the base has lines.
- `tests/test_review_stats.py`: a newer resolution that comes before an older
  one in the log still gives the finding's outcome.
- `tests/test_api_reference.py`: the placeholder step replaces every
  placeholder link with the commit hash. It refuses a placeholder that remains,
  a source link with another hash, and a revision that is not a full commit
  hash. The base build accepts only the placeholder.
- A test that `build-support/api-reference.nix` gives the revision only to the
  cheap step, and that `tools/ci_store_gc.py` roots the revision-free build.
- A local Nix check: two reference builds with different commit hashes build
  the expensive derivation once. The second build runs only the cheap step.
  Its time is recorded in the status file.
- A hosted check: the pull request's own CI passes. After the merge, a later
  pull request that does not change Lean sources restores the base reference
  from the cache. Its time for the reference step is recorded.

## Relevant source and constraints

- `tests/ci_scope.py::is_documentation` and `scope` choose the scope.
  `.github/workflows/ci.yml` runs the `docs` step and the expensive steps by
  scope. A change to `.github/` or `tests/ci_scope.py` itself selects larger
  scopes; that is correct and stays.
- `tools/review_log.py` reads and parses records. The review tools write the
  log; tests always use temporary logs through `SQLITE_VERIFIER_REVIEW_LOG`.
  The log is append-only by the rule in `AGENTS.md`. Merges of main into a
  branch reorder lines, and can keep one copy of a line that both sides
  contain, so the check requires presence, not a position or a count.
  `tools/review_stats.py::latest_outcomes` took the last line as the latest
  outcome, so it uses the resolution date instead.
- `build-support/api-reference.nix` passes `revision` to the derivation, and
  `tools/api_reference.py` puts it in each source link
  (`SOURCE_REPOSITORY/blob/REVISION/PATH#L…`). The derivation therefore changes
  with every commit. The placeholder must not be a valid commit hash, so it
  cannot collide with a real one.
- A built reference is 172 MB with 1,169 pages. Source links occur only in the
  `SqliteVerifier` pages: 270 links in 23 files. The local-link check reads all
  pages; it belongs to the expensive build, because it does not depend on the
  hash.
- CI saves the Nix cache only from `main` and nightly runs. The cleanup in
  `tools/ci_store_gc.py` keeps only the roots of its `TARGETS`; the reference
  is not one of them today. A new root makes the saved cache larger. The
  compressed size of the base reference is recorded in the status file.
- `just reference HASH` keeps its interface. The CI step keeps its name.
