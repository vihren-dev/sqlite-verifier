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

## Validation

Pending: pinned upstream API audit, exact origin/closure design, focused
tests, byte-identical native baseline comparisons, installed runtime checks
on both platforms, independent review and required owner review.
