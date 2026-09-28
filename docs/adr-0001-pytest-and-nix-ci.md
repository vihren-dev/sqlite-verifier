# ADR 0001: Discoverable pytest cases and Nix build caching

- Status: Accepted; implementation in progress
- Date: 2026-09-26
- Updated: 2026-09-28
- Accepted: 2026-09-28 by the product owner
- Repository examined: `2e173c7aa6adca5f4ba4292cba172f8c11a144f7`
- Decision owner: technical lead; product owner accepts changes to test coverage
- Related proposal: ADR 0002, compile-project caching (separate draft)

## 1. Outcome and decision

Adopt pytest for Python test discovery, descriptions, selection,
reporting, and fixtures. Keep Lake for Lean builds. Use Nix
derivations to cache project build outputs. Preserve all existing test
scenarios. Cache results only for deterministic pure unit checks whose complete
inputs are captured. Proof acceptance, conformance evidence, sandbox capability,
installer and installed-runtime checks continue to execute freshly, as specified
in section 4.2. Project build reuse does not authorize reuse of verification verdicts.

Each test scenario must be implemented as a separate pytest test
case. CI should avoid rebuilding unchanged components and rerunning eligible pure
unit checks, while preserving every scenario and the fresh-execution requirements
above. The product owner accepted this ADR on 2026-09-28. Implementation is tracked
in the [task](../plans/20260928-pytest-nix-builds.task.md) and
[status](../plans/20260928-pytest-nix-builds.status.md). The examined baseline has
not implemented pytest discovery or Nix derivations for project builds.

This ADR authorizes the narrow build-output caching change described below in [CI
policy](ci.md), subject to the rollout measurements. The separate [CI performance
task](../plans/20260925-ci-performance.task.md) remains historical
evidence of the previous decision; its supersession note records this acceptance.

## 2. Baseline behavior and implementation evidence

The table below describes the examined baseline commit, not the implementation
branches. It records what this decision changes and what the benchmark must
compare against. The implementation checkpoint follows the baseline measurements;
the linked status file tracks subsequent work and outstanding acceptance checks.

| File | Observation | Consequence |
| --- | --- | --- |
| `tests/atuin_cli_test.py` | Thirteen verifier invocations in one `main()`, with mutation and restoration of shared files | Cannot independently select or time a scenario; one failure prevents later cases |
| `tests/cli_test.py` | Many scenarios in one sequential `main()` | Same selection and failure-isolation problem |
| `tests/kernel_gate_test.py` | Named attacks inside loops and later sequential mutations | Labels are printed, but not independently collected |
| `tests/test_*.py` | Existing `unittest.TestCase` tests | Can migrate the runner before rewriting test bodies |
| `tools/run_independent_suites.py` | Two script workers on Linux, one on macOS | Already has measured platform-specific concurrency constraints |
| `justfile` | Suite-wide limits, including 1500 seconds for Atuin | No case-level performance attribution |
| `nix/flake.nix` | Supplies a development shell and upstream SQLite packages | Does not describe project builds or test results |
| `.github/workflows/ci.yml` | Restores the Nix store, then runs `just` inside `nix develop` | Does not cache arbitrary commands merely because they run in the shell |
| `ProofChecker.lean` | Reuses Lean import state within each verification, retaining comparison, replay, audit and kernel checks | Removes repeated imports within a process; no cross-run build or verdict cache |
| `migration_check/compile.py` | Rejects protected baseline drift before compilation; matching requests still compile isolated source stages | Cached project binaries do not eliminate per-verification source compilation |

The current [performance measurements](ci-performance.md) and
[completed performance task](../plans/20260925-ci-performance.status.md) replace
the earlier 11m46s Linux experiment as the comparison baseline. The examined head
contains documentation closeout after runtime revision `7a99c71f`, released as
v0.1.1. That runtime passed two complete source and installed-package runs:

| Run at `7a99c71f` | Dependency cache | macOS | Linux |
| --- | --- | --- | --- |
| [Main validation](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36387285239) | macOS cold; Linux warm | 14m31s | 9m57s |
| [Release repeat](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36388588408) | Both warm | 14m17s | 8m46s |

These platform-job times include build, tests, packaging, installation, cache work
and artifact uploads; the separate release-publishing job is excluded. Existing
optimizations include early baseline rejection, per-invocation Lean import reuse,
Linux suite overlap, dependency caching and zstd Nix export. Preserve those gains
and package-phase timings when evaluating this proposal. Runner variability means
the two observations are a baseline, not proof of a particular future speedup.

The observed macOS overlap timeout preceded the import-reuse fix. Keep the current
one-worker macOS scheduling initially; any new concurrency claim needs measurements
with the current checker. The 1500-second Atuin suite limit and the 30-second
production checker deadline are unchanged.

### Implementation checkpoint: 2026-09-28

The decision remains relevant, and its implementation is in progress. Reviewed
changes now provide pytest discovery, isolated runtime fixtures, phase reports,
the Nix toolchain/parser/Lean/runtime graph, explicit-root packaging, canonical
cache fingerprints and an explicit pure-unit target. The integrated implementation
has passed complete acceptance on both native platforms. Cache transport and
performance measurements remain in progress.

| Area | Verified implementation evidence | Still required |
| --- | --- | --- |
| Test harness | 422 collected cases reconciled with the inventory; resource-free discovery; nested timeout cleanup; all 416 source and 19 installed cases pass alone and reversed | Performance measurements |
| Source and installed cases | Final native run 36408912201 passes Linux and Darwin; each reports 352 fresh source cases plus 64 disjoint cached unit cases, and 19 installed cases, with every phase passing | Retain the same gates in every benchmark sample |
| Nix outputs | Both native platforms build the graph and pass archive/signature/installation checks; all input-identity and 64 pure-unit checks pass | Demonstrate reuse after a remote cache restore |
| CI transport | Four-job pilot 36410934815 verifies exact warm restoration and output reuse on both platforms; source-mode follow-up 36412764476 also passes; fixes merged as `2aacaa4d` | Full 60-sample run 36414706819 and measured rollout decision |

Implementation evidence is recorded in the [status file](../plans/20260928-pytest-nix-builds.status.md)
and its linked member records. The dependency-cache workflow remains the rollout
fallback. No speedup or completed rollout is claimed by this checkpoint.

## 3. Test design

### 3.1 Discovery and case identity

Add `pytest.ini` with `testpaths = tests`, both existing file patterns
`test_*.py *_test.py`, `--strict-markers`, `--strict-config`, and concise failure
summaries. Add pytest to the Python development environment pinned by
`nix/flake.lock`. Use `pkgs.python3.withPackages (ps: [ ps.pytest ])` for the development/test
interpreter and retain a separate bare `pkgs.python3` for the packaged launcher.
Pass the bare interpreter explicitly to the archive builder rather than bundling
the pytest-bearing interpreter simply because it is running the test harness.

Keep current filenames where they match discovery. Convert and rename
`tests/toolchain_smoke.py` to `tests/test_toolchain_smoke.py`, updating its callers:
the current name matches neither pattern, but its pinned-toolchain and native
SQLite checks remain required. Record this mapping in the scenario inventory.
When converting a script, replace its `main()`
scenario body with named test functions. Pytest imports modules at collection
time: remove import-time builds, filesystem mutation, and subprocesses. Resolve
runtime tools in fixtures, so listing tests works without Lean, Nix, or binaries.

Every collected case has:

1. A stable pytest node ID, including descriptive parameter IDs.
2. A docstring stating the protected behavior, scenario, and expected outcome.
3. Exactly one level marker: `unit`, `integration`, or `e2e`.
4. Zero or more concern markers: `parser`, `kernel`, `approval`, `atuin`,
   `packaging`, `conformance`, `environment`.
5. Complete resource markers: `requires_lean`, `requires_native`, `requires_nix`,
   `requires_sandbox`, as applicable. These describe actual needs, not filenames.
6. `smoke` only for an explicitly reviewed convenience subset.

Keep assertion groups for one behavior together. Use parametrization when only
the input and expected outcome differ; split behaviors that need different
explanations. Do not let loops hide independently meaningful cases. Existing
`unittest` methods may remain while acquiring module/class markers and docstrings;
fixture arguments and pytest parametrization require conversion to pytest functions.

Preserve the current kernel substitution assertions when converting the attack
cases: rejection must identify the protected declaration and report either
`already contains` or `modified protected`. Import reuse can reject a collision
before the later declaration comparison; arbitrary nonzero exit is insufficient.

### 3.2 Required Atuin migration inventory

Each row becomes a separately selectable case. Keep all assertions associated
with the original scenario, including diagnostic and input-manifest checks.

| Suggested case suffix | Expected status | Purpose |
| --- | --- | --- |
| `valid_migration_preserves_history` | VERIFIED | Accept the original migration and verify generated artifacts and exact protected closure |
| `changed_sql_rejects_stale_proof` | UNVERIFIED | Reject the changed field with unchanged proof facts |
| `different_field_preserves_contract` | VERIFIED | Change SQL and candidate facts together while retaining approved meaning |
| `omitted_original_primary_key` | INPUT_ERROR | Detect drift in protected starting schema |
| `unsupported_default` | UNSUPPORTED | Reject unsupported default semantics |
| `drops_history` | UNVERIFIED | Reject dropping a protected business history |
| `erases_commands` | UNVERIFIED | Reject replacing protected command text |
| `weakened_invariant` | UNVERIFIED | Reject removing schema and decoding obligations |
| `schema_approval_bytes_changed` | INPUT_ERROR | Enforce the exact approved schema bytes |
| `approved_source_changed[HistoryModel]` | INPUT_ERROR | Detect approved model drift |
| `approved_source_changed[HistoryDecoding]` | INPUT_ERROR | Detect approved decoder drift |
| `transitive_mapping_changed` | INPUT_ERROR | Detect a changed transitive approved dependency |
| `unfinished_proof` | UNVERIFIED | Reject `sorry`, not merely a timeout |

For the alternative-field case, construct both mutations directly in its fixture.
Do not depend on the stale-proof case running first. Derive expected approved
hashes from the checked-in baseline rather than another test's result.

### 3.3 Fixtures and runtime selection

- A session fixture resolves a runtime root supplied by `--runtime-root PATH`
  (default: source checkout). Validate only the prerequisites required by selected
  cases, so resource-free tests need no built runtime. Fixtures never build implicitly.
- A function fixture copies the relevant example into `tmp_path`, preserving
  the approved/candidate directory boundaries. Each case mutates its own copy.
- A reusable invocation helper captures command, return code, stdout, stderr,
  and elapsed time; invalid JSON produces those diagnostics rather than hiding them.
- Cases requiring a baseline produced by another verification perform that setup
  explicitly in their own fixture. Record setup time separately. Share only
  demonstrably immutable results.
- Kernel common fixtures may be compiled once per suite and copied into each case's
  private directories.
- Missing required tools are a setup error when the case is selected. A developer
  excludes resource markers to run a smaller subset; CI must not silently skip them.

`--runtime-root` selects the executable and examples together. The installed
Atuin run uses the same thirteen collected cases with the installed root, while
the pytest harness runs in the development environment. Preserve the sanitized
child environment and poisoned ambient-import checks in `runtime_package_test.py`.
Do not add pytest to the shipped runtime or replace the isolated installed launcher
with imports of the checkout's `migration_check` package.

This selector does not automatically redirect tests that import implementation
modules or hard-code checkout paths. For example, `compilation_test.py` calls
`compile_project()` directly and selects its library/checker under `ROOT`.
Inventory those consumers and pass their required paths explicitly; distinguish
source-internal tests from installed-entrypoint tests in the runtime variants.

### 3.4 User commands and catalogue

The following is the target interface, available after the corresponding steps:

```sh
nix develop path:./nix
just setup
just build
just test-list
just test-list -m atuin
python -m pytest tests/atuin_cli_test.py::test_changed_sql_rejects_stale_proof -vv
python -m pytest -m 'atuin and approval' -vv --durations=20
python -m pytest -m 'not requires_lean and not requires_native and not requires_nix and not requires_sandbox'
python -m pytest --lf
```

Implement `just test-list *args` using `python -m pytest --collect-only --catalog`
and forward the supplied arguments. `--catalog` is a small repository plugin
option defined in the root `conftest.py`, not an upstream pytest feature.
Loading it at the repository root makes options available even when a catalogue
output file already exists outside `tests/`. After normal
selection, print one record per selected item: node ID, docstring summary,
parameter ID, level, concern markers, and resources. Offer `--catalog-json PATH`
with the same fields, sorted by node ID. Resolve markers through pytest's API;
do not parse Python source with regular expressions. The catalogue must neither
set up fixtures nor perform a build. Validate missing descriptions/unknown markers
at collection. During migration, explicitly label remaining legacy wrappers.

`just test` retains its build/coverage prerequisites and runs the complete source
set. Add `just test-cases *args` for direct pytest selection against an already
built runtime; document this distinction. Do not pass shell-interpolated user
strings through `eval` when implementing argument forwarding.

### 3.5 Logs, timing, and execution limits

Currently CI retains `build/test-logs/*.log` and `build/coverage.json`.
The case-level reports and artifact layout below are proposed additions.

Use `-v --durations=20 --junitxml=build/test-results/RUNTIME/SUITE.xml`, where
`RUNTIME` distinguishes at least `source` and `installed`. Keep output
capture enabled so successful cases are concise. Use pytest report hooks to
record setup/call/teardown durations and failure artifact paths in
`build/test-results/RUNTIME/SUITE.json`; serialize outcomes including setup errors,
timeouts and the runtime variant. Artifact subdirectories use a digest of the
runtime variant and full node ID, with both readable values in a metadata file.
Source and installed Atuin cases can share node IDs without overwriting reports
or failure artifacts. Retain artifacts on
failure and aggregate reports on both success and failure.

Keep bounded subprocess calls and current production deadlines. Timeout cleanup
must kill and await the child process group; merely terminating pytest does not
establish child cleanup. Reuse the semantics of `run_sandboxed` in a test helper
without changing the production sandbox. Any future per-case timeout plugin is
an additional watchdog, not a replacement for child cleanup.

Initially keep existing suite deadlines and Linux/macOS scheduling. Adapt
`run_independent_suites.py` to launch pytest files for the two existing groups;
do not run those files a second time in the remaining full-source selection.
Preserve continuation and awaiting of siblings after a failure. Lower the Atuin
1500-second limit only after measurements; the framework migration alone does
not justify a new number. For a later reduction, use at least three complete
runs per platform and a documented margin above the slowest observed run.

## 4. Nix build design

### 4.1 Preserve the environment boundary

`tools/check_resources.py` and `tests/environment_snapshot_test.py` require
`nix/` to contain exactly `flake.nix` and `flake.lock`, under 1 MiB. Keep this
invariant and `.envrc`'s `path:./nix` entrypoint. A root flake or an unrestricted
parent-directory flake input would undermine the existing snapshot protection.

Put project build expressions in a new `build-support/` directory. Use the ordinary
Nix expression entrypoint `nix-build build-support/default.nix -A TARGET` rather
than adding project sources to the environment flake. Its `pkgs` must come from
the exact `nix/flake.lock` input, never `<nixpkgs>` or a floating channel. Implement
a small helper that reads the lock's root `nixpkgs` node and calls
`builtins.fetchTree` with its locked `type`, `owner`, `repo`, `rev`, and `narHash`;
reject unsupported lock layouts clearly. Use the same helper for all build targets.
The Nix installation already enables flakes; document that `fetchTree` needs that
feature. There is one lock, and no second independently updated pin.
Check `builtins ? fetchTree` under the actual CI Nix version; enable the
`fetch-tree` feature explicitly where required by that version. Do not assume
that every Nix release exposes it under the same experimental-feature setting.

Use `lib.fileset.toSource` in these expressions before converting the selected
source to a store path. Never interpolate the entire checkout as a source. Include
all actual inputs, including generator scripts; exclude `.git`, `.jj`, `.lake`,
`build`, `dist`, and unneeded documentation. Test input identities with added and
deleted files, not only modifications.

### 4.2 Target graph and outputs

| Proposed attribute | Inputs | Outputs / consumer |
| --- | --- | --- |
| `leanToolchain` | Exact version from `lean-toolchain`, platform-specific upstream archive URL and reviewed hash, packaging expression, native toolchain dependencies | Offline Lean/Lake 4.33.0 toolchain |
| `parsers` | Both vendored SQLite source sets and hash manifests, all parser build/generator code and C headers, Nix C toolchain | Both parser executables under `build/` |
| `leanRuntime` | Root Lean files, `SqliteVerifier/**`, Lake config/manifest, pinned Lean and native compiler | `.lake/build/lib/lean` plus `.lake/build/bin/migration-proof-checker` |
| `runtime` | Previous outputs, Python entrypoint/modules, examples and runtime metadata tools | Runtime tree with the existing relative layout |
| `unitChecks` | Explicit resource-free Python test/source files, pytest config/helpers and pinned Python/pytest | JUnit/JSON results for deterministic unit cases |

For each native platform, fetch and hash the actual Lean release archive and
implement loader patching as required; do not invent hashes or select a different
Lean version merely because nixpkgs includes it. Test `lean --version`, Lake build,
and runtime dependency discovery. Build derivations cannot download through Elan.
Keep the existing shell working until this toolchain passes on both platforms.

Keep using Lake inside `leanRuntime`. A changed Lean source may rebuild the whole
Nix derivation in a fresh directory; this proposal does not promise persistent
module-level incremental builds between different derivations. Local `lake build`
continues to provide ordinary incremental development builds.

`runtime` must preserve loader-root metadata, module deletion handling, and the
layout expected by `Runtime.locate()`. Initially CI may copy these immutable
outputs into a fresh runtime staging directory; test fixtures receive that root.
Packaging should accept an explicit build/runtime root instead of implicitly
requiring binaries from the checkout. Inventory `ROOT` references before this
change; make the parser/checker/library paths explicit wherever needed.

Keep pure unit checks cacheable. Execute proof acceptance, conformance evidence,
sandbox capability, Nix installer, and installed-runtime tests freshly on the host
against built artifacts. Do not put nested Bubblewrap or Nix-daemon installation
tests inside a Nix build sandbox or disable isolation to make them pass. A successful
`unitChecks` derivation is not a replacement for `just check` or `just package`.

### 4.3 Transport and invalidation

Use the already pinned `cache-nix-action` first; no external cache subscription
or secret is required. Its pinned `action.yml` supports
`restore-prefixes-first-match`; it is not named `restore-keys`.

Define primary keys as `build-v2-SYSTEM-ENVHASH-SOURCEHASH`. `ENVHASH` covers both
environment pin files and `lean-toolchain`; `SOURCEHASH` covers the complete
build/test source inventory represented by cacheable derivations, including
`build-support/`. Use a canonical sorted path/content manifest so additions,
deletions, and renames affect the fingerprint. Restore the exact key first and,
on a miss, the latest `build-v2-SYSTEM-ENVHASH-` prefix. Nix then chooses outputs
by their derivation identities; restoring older store contents never authorizes
an output for a different input. Only successful main jobs save. PRs and tags
only restore. Preserve action pinning, signature checks, and read-only PR permissions.

This narrowly replaces the old prohibition on prefix restoration and project
build outputs. Never cache checkout `.lake`, user-provided proof workspaces,
ADR 0002's local cache, or final verification verdicts via extra cache paths.
Do not enable purge or automatic GC. GitHub cache archives are immutable, so
the existing constant environment-only primary key cannot accumulate new builds.
Measure store restore/save overhead; cache misses must still work offline after
declared inputs have been fetched. Keep the old dependency-cache scheme available
as rollback if transporting the larger store costs more than rebuilding.

## 5. Implementation work packages

Assign an implementer and a different reviewer to each row. These are suggested
small PR boundaries; do not combine all behavior changes into one migration PR.

| Step | Files / work | Depends on | Completion evidence |
| --- | --- | --- | --- |
| T1 | Inventory every `justfile`/coverage subprocess and every scenario; create `tests/case-inventory.json` mapping old label/location to new node IDs and runtime variants | None | Reviewer accounts for every old assertion group, including script-only `__main__` branches and `toolchain_smoke.py` |
| T2 | `pytest.ini`, `conftest.py`, pytest in `nix/flake.nix`, catalogue, fixtures and reporting | T1 | Collection works without binaries; duplicate/missing IDs and markers fail; existing unittest cases collect |
| T3 | Convert Atuin; reuse all cases in source and installed harnesses | T2 | Thirteen cases selectable independently in each runtime; original outcomes and artifact assertions preserved |
| T4 | Convert CLI, kernel, compilation, baseline, parser and remaining scripts; adapt suite runner and coverage producers | T3 | Inventory has no legacy gaps; no duplicate execution; fresh `coverage.json` retains denominator/completeness checks |
| B1 | `build-support/default.nix`, lock helper, source filesets, Lean toolchain, parser and Lean derivations | T1 | Builds and input-invalidation tests pass on both native platforms; environment boundary unchanged |
| B2 | Runtime-root plumbing, loader metadata, packaging consumers | B1, T3 | Full installed suite passes with poisoned environment, spaces/Unicode paths and network-free installation |
| C1 | Workflow/report retention, selected unit derivation, build-v2 transport, CI scope routing | T4, B2 | Required job names/scopes/release gates retained; cold/warm and changed-input evidence recorded |

`tests/ci_scope.py` must classify `build-support/`, `pytest.ini`, and shared test
configuration changes as full `package` scope. Unknown paths must continue to run
at least full checks. Documentation-only routing remains available without Nix.
`parser_build_test.py` contains both unittest and a special native-reuse path:
inventory both. Coverage scripts are evidence producers as well as tests; keep
their output schema and failure propagation when changing execution entrypoints.

## 6. Acceptance and measurements

- All existing cases appear in the inventory and execute in the required variants.
  No silent omissions from replacing `main()` or changing discovery patterns.
- Selected case runs pass alone and in reversed order with fresh mutable fixtures.
- Catalogue collection requires only Python/pytest; missing execution prerequisites
  fail clearly rather than skipping a required case.
- Failure, setup error, malformed JSON, and timed-out child demonstrations retain
  useful output and fail CI; no child processes survive the timeout test.
- Source and installed runs of the same node ID retain distinct reports and
  artifacts; neither runtime variant replaces the other's evidence.
- A docs edit changes no parser/Lean derivation; changing a parser source or a Lean
  source invalidates the appropriate component; toolchain changes invalidate both
  where applicable. Deleted modules cannot leak from old outputs.
- Both native platform jobs retain all source and installed acceptance coverage,
  protected-baseline checks, signature checks, and the 2 GB archive guard.
- Record at least three runs per platform for cold build, unchanged warm build,
  changed Python test, changed Lean module, and full packaging. Use fresh runners
  and isolated cache namespaces for experiments; do not purge existing caches.
  Record commit, runner image, Nix/toolchain versions, selected IDs, setup/call
  durations, build/cache transfer time, peak disk use, and total elapsed time.
- Accept cache rollout only if correctness gates pass and median end-to-end warm
  CI improves on both platforms without a material cold-run regression. Record
  numbers and any retained platform-specific concurrency, not an estimated speedup.
  Compare against the current optimized implementation above, and rerun that
  implementation under the same benchmark conditions rather than attributing
  historical runner or cache differences to the proposed changes.

Rollback pytest per suite using the old entrypoint until coverage parity is proven.
Rollback build caching through the workflow/recipe change without deleting caches
or changing proof semantics. Retain timing reports to guide the next experiment.

## 7. Alternatives and limitations

- **Bazel:** useful action-level caching and scheduling, but wrapping current scripts
  does not split their internal work. Requires additional Lean/build integration.
- **Only unittest:** already present and usable, but pytest's parametrization,
  fixtures, selection and reporting better match the requested case interface.
- **Cache complete acceptance results:** saves more time but conflicts with the
  current fresh-proof policy and host capability checks; excluded here.
- **Parallelize everything:** conflicts with observed macOS contention; measure first.
- **Immediately shorten the installed Atuin suite:** removes required installed
  coverage; this ADR keeps all thirteen cases. Any smaller CI subset is a separate
  explicit coverage decision.

Nix caching does not accelerate a cold verifier invocation's internal compilation.
The separate ADR 0002 draft addresses that distinct optimization; it is not a
prerequisite for this decision.

## 8. Research references

Consulted 2026-09-26. Repository observations above are tied to the examined commit;
upstream documentation may evolve. Verify APIs against the pinned environment.

- [Pytest selection and durations](https://docs.pytest.org/en/stable/how-to/usage.html)
- [Pytest fixtures and isolation](https://docs.pytest.org/en/stable/how-to/fixtures.html)
- [Existing unittest support and limitations](https://docs.pytest.org/en/stable/how-to/unittest.html)
- [Pytest parametrization](https://docs.pytest.org/en/stable/how-to/parametrize.html)
- [Pytest reporting](https://docs.pytest.org/en/stable/how-to/output.html)
- [Nix filesets and source filtering](https://nix.dev/tutorials/working-with-local-files.html)
- [Nix fetchTree and feature requirements](https://nix.dev/manual/nix/2.35/language/builtins.html)
- [Nix CI and binary caching](https://nix.dev/guides/recipes/continuous-integration-github-actions.html)
- [Pinned cache action input contract](https://github.com/nix-community/cache-nix-action/blob/7df957e333c1e5da7721f60227dbba6d06080569/action.yml)
- [GitHub cache immutability and access rules](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
- [Lake build system](https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/Lake/)
- [Bazel action caching](https://bazel.build/remote/caching)
