# ADR 0005 C2 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [exclusion narrowing](20261001-adr5-c2-exclusions.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

Runtime extraction still accumulates exclusions until reset. Ordinary eval and
single read-only onecolumn/exists calls are supported; row scripts and mixed
helper sequences remain excluded. Selection preserves preceding reasons.
No narrowed extraction rule or yield improvement is claimed yet.

## Progress

- 2026-10-01: Read the Tcl proxy, assertion event consumer and pilot selection
  while C1's full regression ran. Recorded required observable outcomes and
  rejecting tests before implementation; frozen evidence remains unchanged.

- 2026-10-01: Replaced overwriting selection branches with a pure accumulated
  reason policy. Context, failed Tcl expectations, missing SQL observations,
  continuation after an SQL error and the selection cap all survive together.
  Per-instance reports expose the full exclusions array and retain the existing
  result string for consumers. Acquisition failures also enter that array;
  extractor source identity includes the policy module. Upstream/frozen replay
  and document checks: 7 passed in 4.65 seconds. Helper semantics, context
  lifetime narrowing and measured yields remain open.

- 2026-10-01: Runtime candidates retain helper kinds in prefixes and assertions.
  Native acquisition uses the SELECT-only preparation guard and native readonly
  flags for row helpers; writes and setting PRAGMAs are refused. Tcl fidelity
  applies exists/onecolumn semantics to ordinary native rows without changing
  evidence. Tests cover first-column, existence, NULL and empty results, prefix
  helper reads, wrong expectations and writing helpers. Mixed helper sequences
  and row scripts remain named exclusions pending their own faithful checks.
  Split the assertion event consumer out of the 196-line pilot module to keep
  files below 200 lines, preserving its public import. Upstream/record/profile/
  document checks: 26 passed in 5.03 seconds. Built the pinned Tcl testfixture and
  verified actual helper behavior against src/tclsqlite.c and the standalone
  tests/upstream_helpers.tcl check (HELPER_SEMANTICS_OK). C2 remains open.
