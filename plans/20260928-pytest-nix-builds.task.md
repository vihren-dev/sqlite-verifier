# Discoverable tests and cached project builds

Created: 2026-09-28. Status: IN PROGRESS.

## Required outcome

Implement accepted [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md) in full.
Every existing scenario is independently discoverable and selectable through
pytest, with its descriptions, markers, runtime variants and assertions preserved.
Nix builds immutable project artifacts from complete filtered inputs, and CI
reuses those artifacts only when their derivation identities match. Proof verdicts,
conformance evidence, host sandbox checks and installed-runtime acceptance remain
fresh. ADR 0002's proposed local compilation cache is outside this task.

## Observable acceptance

- `tests/case-inventory.json` maps every old assertion group, including script-only
  branches and coverage producers, to collected node IDs and runtime variants.
  No legacy wrappers or hidden scenario loops remain at completion.
- `pytest.ini` enforces discovery, descriptions, registered concern/resource
  markers and exactly one level. Collection and catalogue require only Python and
  pytest; selected missing prerequisites fail setup rather than silently skip.
- `just test-list`, `just test-cases` and the complete `just test` have the behavior
  in the ADR. Selection is safely forwarded. Linux has two kernel/CLI workers,
  macOS one; siblings finish after failure and no selected suite runs twice.
- Each case owns mutable fixtures, passes alone and in reversed order, and reports
  setup/call/teardown timing. Source and installed JUnit/JSON reports and failure
  artifacts cannot overwrite each other. Invalid JSON and timeout diagnostics
  retain command, status, streams and elapsed time. Timeout cleanup kills and
  awaits process groups without changing production limits.
- All thirteen Atuin cases execute through both public runtime entrypoints.
  Protected closure, hashes, generated inputs, diagnostics, kernel substitution
  attacks, initializer/unsafe/partial/axiom/body/target/profile attacks and positive,
  refutation and unfinished-proof coverage remain intact.
- `nix/` remains exactly two regular files under 1 MiB, entered as `path:./nix`.
  Its pinned test interpreter contains pytest; packaged Python does not.
- `nix-build build-support/default.nix -A TARGET` supports `leanToolchain`,
  `parsers`, `leanRuntime`, `runtime` and `unitChecks`, using the single lock pin,
  actual reviewed Lean 4.33.0 archive hashes, explicit filesets and offline builds.
  Both native platforms retain loader roots, current-module filtering and layout.
- Pure unit results alone may be cached. Proof and conformance evidence, sandbox,
  installer and installed tests execute freshly on the host. Packaging accepts an
  explicit runtime root and preserves signatures, offline installation, poisoned
  ambient environment, spaces/Unicode paths and the 2 GB archive limit.
- Build-v2 cache keys hash complete canonical source membership and environment
  inputs. Exact then compatible prefix restoration is safe by derivation identity.
  Only successful main jobs save; PRs/tags restore. No cache purge, automatic GC,
  checkout `.lake`, user proof workspace or final verdict cache is introduced.
- CI keeps required job names, protected-baseline and release gates, docs-only
  routing without Nix, fresh complete `coverage.json` and success/failure reports.
  Shared pytest/build configuration selects package scope; unknown inputs check.
- At least three runs per native platform cover cold, unchanged warm, changed
  Python test, changed Lean module and full package scenarios in isolated cache
  namespaces. Comparable reruns of the optimized baseline record commit, runner,
  versions, selected IDs, case/setup, build/transfer times, peak disk and total time.
  Cache rollout requires improved median warm end-to-end time on both platforms
  and no material cold regression. Measurements, not estimates, support claims.

## Verification and design constraints

Review inventory parity against the baseline source at `4df62fa7`; use actual
collection output to verify the map. Exercise independent/reversed selections,
missing tools, malformed JSON, failing setup, child-process timeout cleanup and
runtime artifact separation. Test additions/deletions/renames as well as edits:
docs must not invalidate parser/Lean builds; actual inputs must invalidate their
consumers. Run complete source, conformance and installed suites on both platforms.

Important existing consumers are `justfile`, `conformance/coverage_report.py`,
`tools/run_independent_suites.py`, `migration_check/compile.py`,
`packaging/build_runtime.py`, `packaging/runtime_dependencies.py` and
`tests/runtime_package_test.py`. Direct implementation imports need explicit
paths; an executable-root fixture cannot redirect them. Preserve early baseline
rejection, per-invocation import reuse, independent proof replay, all deadlines,
zstd export and resource checks. Keep each reviewed change in a separate jj commit
and record its evidence in the status file. Lead integrates member workspaces.
