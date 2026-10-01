# ADR 0005 C2 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [exclusion narrowing](20261001-adr5-c2-exclusions.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

Runtime extraction still accumulates exclusions until reset and only accepts
ordinary eval calls without row scripts. Selection now preserves preceding reasons.
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
