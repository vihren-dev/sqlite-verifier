# ADR 0001 scenario inventory status

Created: 2026-09-28. T1: DONE and independently reviewed. T4 conversion: DONE; lead review pending.

Task: [Discoverable tests and cached project builds](20260928-pytest-nix-builds.task.md).
Decision: [Accepted ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md).
Delivery owner: adr1_inventory (SQLite/conformance test inventory).
Reviewers: integration lead, then formal_preservation independent reviewer.
Workspace: sqlite-verifier-adr1-tests; implementation base eb8e3c94.

## Delivered behavior

[case-inventory.json](../tests/case-inventory.json) records 238 proposed stable
pytest node IDs, source ranges, legacy labels, assertion contracts, runtime
variants, level/concern/resource classifications and orchestration routes.
It includes all 50 existing unittest methods, retaining their nested variants
verbatim as permitted by the ADR; 13 Atuin cases in source and installed runtimes;
18 kernel scenarios; both parser releases; native-reuse; toolchain smoke;
coverage subprocesses and report completeness. Proposed IDs must be reconciled
with actual pytest collection during conversion; this inventory does not claim
that the new cases exist yet.

39 source hashes match baseline 4df62fa71ec64d0eb4b7aa4643a0912ab60e18a9.
Direct implementation consumers remain source-only. Real Nix loader assertions,
installer tests and native-parser unittest consumers have explicit resource
requirements and are excluded from pure-unit result caching.

## Checks and review

- Parsed JSON, checked unique IDs, mandatory fields, valid levels and absence of
  external resources on unit cases using a bounded Python structural check.
- Enumerated all existing unittest methods and checked exact retained IDs.
- Checked every Python `assert` source location in baseline tests is accounted
  for by a case or shared fixture/helper contract; verified 13 Atuin and 18 kernel
  scenario counts. Every recorded source hash was compared with `jj file show`
  at the baseline revision, with a 10-second command timeout.
- Read actual script bodies, loops, conformance producers and unittest methods;
  structural extraction supplements that review rather than defining scenarios.
- Independent draft feedback corrected explicit CompileError contracts for
  artifact aliases, opposite compilation expectations in early-baseline cases,
  quoted module-path equality, exact source ranges and installed GC-root checks.
- No build or runtime execution needed for this data-only change. Production
  sources, test implementations, Nix and shared pytest configuration unchanged.

## Remaining handoff

Independent reviewer formal_preservation approved the corrected T1 inventory.
Root assigned the following bounded T4 conversion. Kernel partial-proof coverage is an accepted-task addition
reported by the independent reviewer, not a falsely claimed legacy scenario.


## T4 conversion evidence (2026-09-28)

Converted parser scenarios (76), pinned-toolchain checks (5), snapshot variants
(2), generated-schema checks (3), upstream/model/native-history scenarios (14),
and native-reuse (2) into independently collected pytest cases. Existing unittest
methods have per-method metadata; selected parser fixtures redirect implementation
consumers to the supplied runtime. Sandbox tests now expose seven separate cases,
with resource-free validation separated from real host isolation.

Minimal conformance helper selections preserve default producer report schemas;
selected upstream calls replay their required connection prefix. Generated Lean
checks use explicit compiler/library fixtures and temporary source files, so the
selected immutable runtime never receives compilation output. Root authorized
these three conformance seams. Legacy evidence entrypoints remain callable until
root reroutes aggregation, and pytest never wraps an entire legacy `main()`.

The inventory now contains 244 proposed IDs; all 159 converted owned IDs exactly
match strict collection. Collection performed no builds and needed no source
runtime artifacts. The source-only native-reuse scenarios intentionally use the
checkout's parser stamps/compiler identity, independently of `--runtime-root`.
The integration recipe retains the prerequisite source parser build.

Checks used one pinned `nix develop path:./nix` shell, after resource preflight:

- Stdlib-only docs script and all four CI-routing unittest methods passed before
  entering Nix. These two modules do not import pytest; shared plugin metadata
  preserves the docs-only route.
- Strict collection: 173 total IDs, including 14 shared plugin checks; all 159
  owned IDs matched the inventory without omissions or unexpected additions.
- First executable run: 167 passed, four sandbox failures, two native-reuse cases
  deselected. The pytest-bearing Nix interpreter wrapper needs another executable
  during startup, correctly denied by the existing macOS sandbox policy.
- The sandbox child now uses the already-provided bare `SQLITE_VERIFIER_PYTHON`;
  production isolation remains unchanged. All seven sandbox cases passed.
- All 157 owned cases not needing checkout build stamps passed in explicit
  reversed selection, with 155 retained unittest subtests, in 44.35 seconds.
  Runtime: `/nix/store/vzpcnwzpxgd31pl35g1qf8ziqasxsfav-sqlite-verifier-runtime-1`.
- An independently selected retained-create-prefix model case passed alone in 1.26
  seconds. Final upstream observations also retain a complete report receipt for
  root aggregation.
- Reports remain at `build/test-results/source/t4-focused.{json,xml}`,
  `t4-sandbox.{json,xml}`, `t4-reversed.{json,xml}` and `t4-alone.{json,xml}`;
  source-owned output is retained, not removed.

Root reviews/integrates the conversion, reroutes just/coverage orchestration and
runs the two real source-native-reuse scenarios after its parser build. No
production verifier, Nix, justfile or shared plugin files changed in this commit.


## T4 source-boundary conversion (2026-09-28)

Status: DONE; all execution checks pass, independently reviewed; lead integration pending.

Compilation tests now expose all 17 mapped cases and early-baseline tests all
seven. A 135-line source fixture module gives each mutation fresh approved and
candidate inputs. Compiler, library, checker and parser paths come from explicit
runtime fixtures. Imported verification redirects only `Runtime.locate`; real
parsing, closure discovery, source snapshots, compilation and kernel verification
remain in use. Installed runtime selection fails setup for these source imports.

The selected generated source role rejects before tool access and is a resource-
free unit case, alongside emitted symlink, parent alias, hardlink and module-path
checks. Header graph failures also assert that compilation never begins. Drift
cases retain an invalid proof and require the exact early diagnostic with no
compiler call; the snapshot-positive case instead requires compilation and exact
approved digests after the original files are mutated.

Strict collection matched all 24 inventory IDs. Five resource-free checks pass.
The full 24-case run passed in 27.07 seconds and explicit reversed selection
passed in 23.90 seconds against the immutable Nix runtime.
An explicit installed selection of the module-path case failed during setup with
its source-only diagnostic, as required; its report is retained under
`build/test-results/installed/source-installed-rejection.json`.

A pinned-shell daemon denial was resolved through the supported execution-tool
escalation after lead feedback. No toolchain/configuration workaround was added.
Heavy Lean tests are serialized with the lead and formal reviewer to preserve the
measured macOS single-worker constraint.


Independent reviewer formal_preservation found no blocking parity or independence
issue in this conversion: source hashes, generated binding, sandbox read/write
probes, artifact errors, source graph checks, invalid-proof precedence and sealed
snapshot compilation assertions remain intact. Root owns integration review.


All 24 cases also passed when each was launched alone in a fresh pytest process
(32.51 seconds combined, 90-second outer deadline for each invocation). Reports:
`build/test-results/source/source-boundaries-full.{json,xml}`,
`source-boundaries-reversed.{json,xml}`, per-case `source-boundary-alone-NN` reports
and `build/test-results/source-boundaries-alone.log`. The heavyweight window was
released to the formal reviewer after completion. No production file or shared
plugin file changed in this source-boundary commit.
