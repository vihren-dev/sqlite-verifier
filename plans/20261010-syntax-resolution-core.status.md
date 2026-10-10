# Status: syntax and resolution core, step 1a of ADR 0008

Created 2026-10-10. Status: IN PROGRESS.
Task: [task](20261010-syntax-resolution-core.task.md).
Specification: [ADR 0008](../docs/adr-0008-syntax-and-resolution-in-lean.md).

Relevant files: `packages/belay-sqlite/Belay/Sqlite/`,
`packages/belay-sqlite/lakefile.toml`, `conformance/requirements-3.51.0.json`.

## Findings

- Dependents of the replaced model (survey, 2026-10-10): about 1,100 lines of
  theorem and example bodies use `Schema`, `Statement` or `runSql`; the gate
  names the generated declarations in `GateCore.expectedTarget`; the bundle
  checker builds `nextSchema`, `script` and `profile` from the structural
  record; Python computes `nextSchema` with `transition`; 8 approved files
  mention the replaced names, and their `baseline.json` hashes are written by
  hand.
- Baseline build times on `main` (`5a813d20`), forced rebuild with
  `nix-build --check` in the sandbox, Linux amd64: `modelPackage` 7 s,
  `leanRuntime` 13 s, `conformanceRuntime` 17 s, `publicDocumentation` 5 s.

## Progress

- 2026-10-10: PR #79 merged first (owner decision). Task and status files
  created in the jj workspace `adr8-step1`.

## Remaining

- Everything in the task file.
