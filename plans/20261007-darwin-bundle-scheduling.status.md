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
