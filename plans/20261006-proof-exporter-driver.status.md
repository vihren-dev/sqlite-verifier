# Proof exporter driver status

Status: IN PROGRESS. Created 2026-10-06.

Technical acceptance and independent reviews are complete. The owner approved
PR #47 at reviewed head `07dc71b3` on 2026-10-07. Both export-path review
findings are resolved. The approved Lean upgrade is merged. Integrated hosted
acceptance remains failing on Darwin's whole bundle-suite deadline; merge and
release remain pending. The bounded correction is described in
[the Darwin CI task](20261007-darwin-bundle-scheduling.task.md).

Task: [proof exporter driver](20261006-proof-exporter-driver.task.md).
Source: [issue #29](https://github.com/vihren-dev/sqlite-verifier/issues/29).

## Progress

- 2026-10-06: Preserved the replay-headroom workspace unchanged while its
  deadline specification question awaits owner feedback. Inspected the idle
  catalog workspace; it was clean after the reviewed catalog task. Started
  a new change there from reviewed Lean 4.34.1 revision `6917e3c8`.
- 2026-10-06: Read the approved T02 card and actual issue #29, which has no
  comments. Read the installed exporter invocation, source/contract discovery,
  bundle checker, trusted-base construction and Nix dependency/runtime graph.
  Created the task before feature changes. Root is running a separate native
  check, so exporter builds and measurements await an idle slot.
- 2026-10-06: The checker base is `SqliteVerifier` plus trusted external
  imports. Approved contract and generated input modules are replayed
  separately and must not be treated as omitted library modules. Candidate
  source discovery already distinguishes installed `.olean` imports from
  caller-owned source modules without using a namespace-prefix test.
- 2026-10-06: Audited the unpatched upstream source already in the store,
  at commit `076e8e57707e813375e8f9da8bf989799ace9680`. Its state and exporter
  interfaces support the issue prototype. `dumpConstant` excludes unsafe
  and partial declarations unless the explicit upstream unsafe option is
  selected. Lean 4.34.1 provides declaration-origin indices and module
  indices with direct import arrays.
- 2026-10-06: Verified retained Darwin baseline bytes against the T03 receipt.
  Both platform receipts contain the same three bundle hashes and lengths.
  They bind the unchanged approved, candidate and SQL inputs. Retained
  baseline bytes remain outside this task's workspace.
- 2026-10-06: Minimal design: `ProofExporter.lean` imports unpatched `Export`,
  computes the closure of explicit omission modules, rejects absent modules,
  and marks exactly their origin-bound declarations as visited. Upstream
  emission and metadata remain unchanged. `prepare` supplies the protected
  `SqliteVerifier` base plus the exact sorted imports in its bundle header.
  Approved and generated modules stay outside this omission set. No package
  name or namespace prefix selects omitted declarations, including when the
  model moves to a separate Lake package.
- 2026-10-06: `leanRuntime` will build and install `migration-proof-exporter`.
  Runtime location and isolated Nix test expressions will use that executable.
  The patch and patched producer derivation are removed. The fixed-output
  source pin supplies the unpatched library. `packaging/build_runtime.py`
  already exports the complete runtime closure and needs no special exporter
  staging. Corrected that factual file reference before feature edits.
- 2026-10-06: The coordinator authorized implementation after this correction
  commit. Final owner review still gates publication and release. No actual
  task design conflict was found. Heavy builds await an idle host slot.
- 2026-10-06: The first actual runtime build passed. Focused native checks
  completed with 36 passes and one failure in 181.40 seconds. All three
  baseline input/hash/status comparisons passed, as did existing bundle
  rejection and generated-input parity checks. The library-like candidate
  exposed Lean's package-directory lookup: the installed `SqliteVerifier`
  directory hid a distinct caller-owned `SqliteVerifier.Candidate` artifact.
- 2026-10-06: The coordinator authorized the required lookup correction.
  The compiler and exporter now use the same temporary merged view only for
  split package directories. Original ordered roots select each file; pinned
  artifacts retain precedence over candidate collisions. The checker roots
  and declaration-origin omission logic are unchanged. Two pure regressions
  passed in 0.52 seconds. An actual Lean collision check and rerun of the
  namespace export test are pending.
- 2026-10-06: Actual Lean collision checks passed: the first root's definition
  remains in force despite a conflicting candidate artifact, and the caller's
  distinct sibling module remains usable. Three checks passed in 4.15 seconds.
  The new producer's transitive-origin check passed in 2.11 seconds: trusted
  declarations in an unrelated namespace were omitted while the caller-owned
  declaration in a trusted-looking namespace was exported.
- 2026-10-06: `just test` completed successfully using runtime
  `/nix/store/2hr0i77lmkabqxk0r7h1rsp2mbq5fga8-sqlite-verifier-runtime-1`.
  Source JUnit records 353 checks, with no failures, errors or skips. All six
  development Nix suites passed: Atuin 12, bundle 42, CLI 13, kernel 19,
  sample 12 and upstream 58. The final bundle suite includes the new
  transitive-origin check. The suite and child deadlines are unchanged.
- 2026-10-06: The Nix input/staging checks completed with 72 passes in
  82.62 seconds. They cover the modified isolated runtime expression,
  source identities, test-target invalidation and offline packaging boundaries.
- 2026-10-06: Built an actual Darwin offline archive, retaining Nix content
  verification. Installed acceptance is running through that archive with
  poisoned ambient imports, including the new exporter checks. The current
  self-contained implementation is ready for independent review. Native Linux
  and required final owner review remain pending.
- 2026-10-06: Claude reviewed implementation `79e844a5`. It reported the
  two expected R8 owner-review gates for the export path and new driver,
  with no correctness defect. One R9 recommendation asks the closure
  docstring to state its purpose. Clarified that the closure identifies
  checker-provided declarations for exact omission. Required owner approval
  remains pending in the separate review packet before release or merge.
- 2026-10-06: The actual offline-installed Darwin archive passed all 30
  installed cases in 155.57 seconds. These include the existing installed
  data path and Atuin acceptance, the three exact byte baselines, the
  library-like caller module, argument failures and transitive-origin checks.
  Ambient Python and Lean import paths were poisoned by the installed fixtures.
- 2026-10-06: Recorded both R8 findings as deferred final owner-review gates
  and the R9 docstring finding as fixed, using the append-only review command.
  The owner has not approved this change. The coordinator reserved the idle
  Linux host for actual native build and installed acceptance after the
  correction review. No performance comparison is inferred from these checks.
- 2026-10-06: Docstring correction `5a18b5bf` rebuilt successfully and passed
  Claude review with no findings (`20261006T143032Z-5a18b5bf`). The exporter and
  both checker executable hashes are identical before and after that correction.
- 2026-10-06: Completed native Linux validation in a new reserved-host
  directory from public tracked source `5a18b5bf`. Verified archive and helper
  hashes before extraction. `just test`, all six development Nix suites and
  `just test-nix` passed. The actual installed archive passed 21 original cases
  and all nine exporter-specific cases. All new exporter cases have zero skips.
  Linux's source suite retains two existing optional reviewer-CLI skips.
- 2026-10-06: The Linux driver exited with code 0. Retained its original
  JUnit bytes, receipt, executed helper and source inventory. Independently
  verified all raw XML digests, counts and mandatory exact-byte/origin cases.
  All 823 tracked source files still match after the run. Released host compute;
  prior T03 and T04b evidence directories remain untouched.
- 2026-10-06: Both-platform evidence is in
  [the execution packet](../reports/20261006-proof-exporter-driver/README.md).
  Technical acceptance is complete. The final packet review and required owner
  review remain pending; no push, publication, merge or release occurred.
  The T03 comparison is a fixed-input checkpoint. Later planned proof-input
  changes require new current-example expectations while retaining the original
  baseline receipts.
- 2026-10-06: Final execution packet `35b6dbee` passed Claude review with no
  findings (`20261006T150137Z-35b6dbee`). All implementation recommendations
  are resolved. The two original R8 findings remain deferred for the required
  owner approval. Both-platform acceptance and retained evidence are complete;
  the task is ready for that final review. The packet-review journal line
  remains pending for integration, preserving the append-only log.

## Validation

Technical acceptance is complete: pinned upstream API audit, exact
origin/closure design, focused tests, byte-identical native baseline
comparisons, installed runtime checks on both platforms and independent
reviews. Final owner approval is recorded in the linked owner packet.
Publication integration remains pending; retained execution evidence applies
to the reviewed implementation.

- 2026-10-06: Preparing a draft pull request against the Lean upgrade branch,
  so the exporter change has a separate review from its prerequisite. Retained
  the final packet-review entry. Draft review preparation does not grant the
  R8 approval or authorize merge and release before that approval.
- 2026-10-07: The owner explicitly approved PR #47 in the implementation
  chat at unchanged reviewed head `07dc71b323808ac03991407e75dd4e74031924cb`.
  Recorded approval in the owner packet and resolved both exporter R8
  findings. The original hosted Linux, macOS and protected-baseline checks
  pass. Its upgrade prerequisite has a reviewed publication integration
  at `be59f4d3`; exporter integration will retain the approved source and
  exact baseline receipts. The task remains IN PROGRESS until delivery.
- 2026-10-07: Integrated the approved exporter/approval parent `2a4a2060` with
  merged approved upgrade `bc9e2dce`. Only the append-only journal conflicted.
  Retained every exact row, order and multiplicity: 28 approval/exporter rows
  plus 71 main rows share 18 inherited rows, yielding 81 retained rows. The
  pending `79fe3504` review is retained.
  All 101 checked exporter/prepare/import-view/pin/baseline and historical
  receipt files are byte-exact `07dc71b3`; the removed patch remains absent.
- Both native platforms' evaluated Lean/exporter, parser and conformance source
  and derivation identities match the approved implementation. Main changes
  `migration_check/sql_model.py` and `profiles.py` for accepted engine settings,
  so the assembled runtime source and derivation identities differ. The
  coordinator authorized qualified historical acceptance plus bounded actual
  current-caller checks; no same-runtime claim or fresh full-model/ordinary/
  installed rerun is made.
- Built only fresh Darwin runtime assembly
  `/nix/store/dsb751zkkicbqgxca8lkk3zf4rcz8i85-sqlite-verifier-runtime-1` over
  unchanged reviewed Lean/exporter artifacts. All 12 existing exporter/import
  view tests pass without skips in 52.78 seconds (420-second group bound,
  unchanged child deadlines). The actual fixed small/refutation/Atuin bundles
  remain 11,358 / 14,584 / 1,541,403 bytes with original digests and
  VERIFIED / VIOLATED / VERIFIED statuses. Library-like candidate export,
  transitive origin omission and real trusted-file collision tests pass.
- Actual rendered-command/both-platform routing checks pass 3 tests in 8.50
  seconds; all six CI-routing checks pass in 0.61 seconds. Current headers,
  input/bundle hashes, runtime/executable identities and original JUnit are
  retained separately in
  [the integration receipt](../reports/20261007-proof-exporter-integration/summary.json).
  Linux current runtime identities were evaluated, not freshly built or tested
  here; hosted CI will cover the combined source. Both T03/T02 historical
  receipt directories are unchanged. Darwin slot released to the T04c agent.
  Task remains IN PROGRESS pending integration review and normal PR delivery.
- Integration `128a2019` passed required independent Claude review with no
  findings (`20261007T075456Z-128a2019`). Clarified its unclassified wording
  note: the two parent journals share 18 inherited rows, which explains the
  retained total of 81. Every original row/order/multiplicity is preserved;
  no source, input, runtime or receipt payload changes in this clarification.
- Clarification `28556a43` passed required Claude review with no findings
  (`20261007T075736Z-28556a43`). Published only `tasks/proof-exporter`, retargeted
  PR #47 to main and marked it ready. Its fresh native CI run is `37590714910`;
  protected-baseline checks pass at that reviewed head.
- After PR #44's normal merge as `b91e5cb5`, GitHub reported a publication
  conflict. Refreshed the feature branch with that reviewed main tip. The only
  conflict is the journal; the incoming ADR and two plan files remain byte-exact.
  Retained 83 own rows and 76 main rows, with 71 shared inherited occurrences,
  as 88 rows preserving every exact row/order/multiplicity, including the final
  `28556a43` review. All 101 approved files, deliberate removals and existing
  current/historical receipt bytes remain exact. Only docs/journal paths change;
  runtime/source selections and accepted test inputs are unchanged. No native
  rebuild, model, installed or performance rerun is needed for this refresh.
- The two existing authored-link checks pass in 0.72 seconds. All six prior
  current integration receipt files are byte-exact against `28556a43`. The
  [refresh record](../reports/20261007-proof-exporter-integration/b91-refresh.json)
  retains incoming document and journal hashes plus the original link JUnit
  digest. Task remains IN PROGRESS pending refreshed publication/hosted checks.
- Refresh `10ae1399` passed required Claude review with no findings
  (`20261007T080853Z-10ae1399`). Corrected its unclassified receipt-count wording
  to six prior receipt files and the recorded link-test duration to 0.72 seconds.
  This status-only correction changes no source, runtime, input, journal or
  receipt payload. The final raw refresh review stays preserved in the working
  copy; the reviewed feature is ready for PR #47-only publication.
