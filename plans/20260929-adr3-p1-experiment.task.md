# ADR 0003 P1 comparative experiment

Created 2026-09-29. Status: IN PROGRESS.
Status file: [status](20260929-adr3-p1-experiment.status.md).
Spec: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md), sections "Data path,
if adopted", "Approved contract reuse", "Plan" and "P1 measurements and decision
rule". Owner scope (2026-09-29): P1 only; Linux measured through a manually
triggered GitHub workflow.

## Observable behavior when done

Tuning prototype:

- The kernel gate imports only the trusted modules the request's user modules
  import (always including `SqliteVerifier`), instead of all of `Lean`.
- With an explicitly configured verifier-owned stage store, `verify` reuses
  compiled generated `SchemaInputs`/`SqlInputs` stages and falls back to fresh
  compilation on any miss. Approved closures are reused only if listed in an
  eligibility registry (empty) or under an explicitly named measurement-only
  override. Without configuration, behavior is unchanged.

Data-path prototype (experimental commands, trusted execution):

- `migration-check prepare` compiles the approved contract and candidate modules
  incrementally in a caller-chosen agent workspace and writes a bundle: a header
  line plus a lean4export NDJSON export that omits trusted-library declarations.
- `migration-check verify-bundle` parses the actual SQL, compiles (or reuses) the
  contract and generated inputs, and runs a bundle checker that never compiles
  candidate source. It gives the same statuses and exit codes as `verify`.
- lean4export v4.33.0 (pinned, with the skip-trusted patch) and the bundle
  checker are built by Nix and shipped in the runtime.

Measurement:

- A harness measures today's `verify`, tuning and the data path over the ADR's
  matrix and writes JSON results plus a report that applies the decision rule.
- A manual GitHub workflow runs the harness on Linux and uploads the results.
- macOS results are recorded; the decision remains open until Linux results exist.

## Tests

- Existing kernel-gate, CLI, Atuin and compilation suites pass with the narrowed
  gate imports.
- Stage-store cases: reuse gives the same status, a changed input recompiles, a
  corrupted or missing entry falls back to fresh compilation, and approved
  closures are not reused without eligibility.
- Bundle cases through the runtime entrypoints: positive, refutation, allowed
  failure and Atuin give the same statuses as `verify`; a bundle prepared against
  a modified approved contract, `sorry`, a forbidden axiom and a wrong target are
  rejected.

## Tricky points

- lean4export strips metadata and sets `let` nondep flags to false; protected
  comparison must normalize both sides and compare complete records.
- A library-omitted bundle references library names it does not define; the
  checker must import every trusted module those names come from, resolving them
  only from the sysroot and verifier library.
- Comparator issue #93: replay must happen in an environment with `Init` loaded.
- The existing gate's `additions` treats constants missing from the base as fresh,
  so a narrower base stays sound but can be slower if it misses a module.
- Nix builds are offline; lean4export must be a fixed-output fetch and a Lake path
  dependency populated inside the derivation.
- Files stay under 200 lines; `compile.py` is close to that limit.
