# ADR 0003 P2: data path as the supported interface

Created 2026-09-29. Status: IN PROGRESS.
Status file: [status](20260929-adr3-p2-data-path.status.md).
Spec: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md), "Owner decision",
"Data path (adopted)", "Approved contract reuse" and the P2 row of "Plan".
Evidence: [P1 results](../experiments/adr-0003-latency/p1-results.md).

## Observable behavior when done

- `prepare` recompiles a candidate module only when its own source, or anything it
  imports directly or transitively, changed. Imports of the approved contract,
  `SchemaInputs` and `SqlInputs` are tracked separately, so a migration SQL edit
  does not recompile modules that do not import `SqlInputs`.
- `prepare` and `verify-bundle` are supported commands: no "experimental" wording
  in help, a documented JSON report for each, and the same status/exit-code
  contract as `verify`.
- The installed runtime runs both commands: installed acceptance covers a
  prepared-and-verified positive case, a refutation and a rejected bundle.
- Tuning's narrowed gate imports, the opt-in stage store and the eligibility
  registry stay as they are.
- The library-omitting export option has a recorded decision: proposed upstream,
  or kept as a pinned patch with a documented maintenance procedure.
- The P1 matrix is re-run on macOS and Linux; SQL-edit cells are reported against
  tuning with any remaining gap explained; no data-path cell is slower than
  today's `verify` beyond measurement noise.

## Tests

- Unit tests for the dependency-aware keys: a proof-only edit changes only the
  edited module's key and its importers; an `SqlInputs` change leaves modules that
  do not import it unchanged; an approved-contract change invalidates every module
  that imports the contract.
- The bundle suite keeps passing, plus a case that prepares twice with a SQL edit
  in between and checks both bundles verify.
- Installed acceptance cases for `prepare` and `verify-bundle`.

## Tricky points

- `discover_sources` skips `available` imports before recording them, so the
  prepare step needs each module's full import list, not only local edges.
- Approved modules and `SchemaInputs` change together from a candidate's point of
  view: an approved `.olean` depends on `SchemaInputs`.
- `SqlInputs` depends on `SchemaInputs`; its identity must include both.
- Reused agent-cache entries are untrusted; `verify-bundle` rechecks everything.
- Files stay under 200 lines; `source_closure.py` is at 172.
