# ADR 0001 scenario inventory status

Created: 2026-09-28. T1 authoring: DONE; independent review pending.

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

Lead and independent reviewer approve inventory; root assigns subsequent
conversion ownership. Kernel partial-proof coverage is an accepted-task addition
reported by the independent reviewer, not a falsely claimed legacy scenario.
