# Bounded generation and regression freezing

Created 2026-09-29. Status: ACTIVE.
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Required outcomes

Hypothesis state machines generate both well-scoped and error-seeking scripts with fixed-seed CI and bounded on-demand long runs. Generated statements round-trip through the production frontend. Native and compiled comparisons share the Lean authority. Shrunk disagreements preserve signatures, are classified in a mismatch log, and resolved cases receive kernel regressions. Before long runs, a transaction/DML profile identifies and fixes the dominant acquisition/classification cost.

## Observable validation

Fixed-seed checks exercise both modes and boundary values within existing test budgets, injected disagreements shrink reproducibly, preserved regressions pass kernel/axiom checks, and native W5 properties hold. Record stage timing on transaction/DML workloads.

## Constraints and relevant code

Reuse conformance pipeline, Hypothesis shrinking and stdlib. Add Hypothesis to pinned Nix inputs. Do not edit recorded native observations to resolve a mismatch. Long fuzzing never gates ordinary development.

Work stays in the dedicated adr4 workspace. No merge to main or adr3 rebase before user approval.
