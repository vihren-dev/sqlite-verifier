# Proof exporter driver status

Status: IN PROGRESS. Created 2026-10-06.

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

## Validation

Pending: pinned upstream API audit, exact origin/closure design, focused
tests, byte-identical native baseline comparisons, installed runtime checks
on both platforms, independent review and required owner review.
