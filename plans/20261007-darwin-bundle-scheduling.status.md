# Darwin bundle scheduling status

Status: IN PROGRESS. Created 2026-10-07.

Task: [complete Darwin CI](20261007-darwin-bundle-scheduling.task.md).
Related task: [proof exporter](20261006-proof-exporter-driver.task.md).
Sources: `tools/ci_checks.py`, `tests/test_ci_checks.py`,
`build-support/tests.nix`, `tests/nix_suites.json`, `.github/workflows/ci.yml`.

## Evidence

PR47 head `555b9a745a21755e32d3da3aa98a78c30629e8fe`, run `37592057921`,
Darwin job `112695903532`, failed the bundle builder with exit 124 at its
420-second suite deadline. PR48 head
`8e10a593bf830c272bf6b5e6af525d943ce90212`, run `37592618106`, Darwin job
`112697693167`, failed the same way. Both logs show 20 of 42 cases passed and
the first stage-reuse case active. They contain no assertion failure or
completed bundle JUnit report. Both Linux jobs passed their full gates.

The original PR47 head `07dc71b3` passed the 42-case Darwin bundle in 324.20
seconds. Main `bc9e2dce` freshly passed a smaller 33-case bundle in 214.88
seconds. Later main `b91e5cb5` and tag `v0.1.2` reused that exact cached
33-case output, so they are not fresh comparisons with the 42-case suite.

The one isolated local reproduction used the exact failed PR47 derivation
and runtime. Session `38537` exited 0: 42 passed, zero skips, in 235.46
seconds. The outer build took 236.981429125 seconds. All source, runtime and
pytest identities were equal before and after. No cached result was counted
as fresh, and no output was deleted or rebuilt with `--check`. Original
streams, JUnit, boundaries and identities are retained under
`build/20261007-pr47-isolated-bundle/` for public evidence retention.

## Progress

- Defined complete-gate behavior, failure retention, unchanged suite limits
  and required hosted acceptance before implementation.
- Clarified that the seven existing targets contain six default 420-second
  targets, including bundle, and one 600-second model target.
- Approved exporter sources and protected baseline bytes remain unchanged.
  The earlier raw review journal row remains pending for the next checked
  implementation commit.
- Implementation, bounded checks, independent review and new hosted
  acceptance remain pending. No publication occurred in this preparation unit.
- Added the Darwin-only sequential `tests.bundle` prebuild before the complete
  recipe. Its output uses the existing `build/nix-tests*` artifact path. Linux
  scheduling, all seven complete targets and every suite guard are unchanged.
- Bounded scheduling, real failure/timeout artifact retention, CI routing and
  documentation checks: 15 passed and 28 subtests passed in 3.19 seconds.
  The actual rendered Nix ownership/guard check passed in 1.69 seconds.
  An earlier incorrect test-name selection collected no tests; it was corrected
  before the check. No empty selection is counted as a pass.
- Retained all twelve isolated originals and their original digest manifest,
  the metadata helper and both complete hosted failure logs as 16 gzip payloads.
  The bounded read-only validator passed. Original receipt bytes are unchanged.
- Independent review, latest-main metadata integration and new hosted acceptance
  remain pending. The isolated native reproduction was not repeated.
- Review `20261007T090030Z-02f434b3` completed with no must findings and three
  should findings. Named the hardened build options and retained counts, added
  actionable receipt diagnostics, and checked that corrupted archived identity
  bytes fail. The correction does not change a command, suite or receipt byte.
- Correction checks passed: 16 tests and 28 subtests in 3.15 seconds; the
  retained-evidence validator passed again. All three findings are recorded
  fixed in the append-only journal. Correction review and publication remain
  pending.
- Review `20261007T090510Z-1c43cbb1` found no must findings and one should
  finding: the named isolation options also need a drift check against the
  actual complete `justfile` recipes. Added that direct source check and
  removed the redundant comparison with a copied literal.
- The drift check initially tried to parse comments as shell commands and
  failed on a prose apostrophe. Restricted it to actual Nix command lines.
  The final bounded suite passed 17 tests and 28 subtests in 3.15 seconds.
  Recorded the remaining finding fixed; final correction review remains pending.
