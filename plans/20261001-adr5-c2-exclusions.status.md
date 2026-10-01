# ADR 0005 C2 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [exclusion narrowing](20261001-adr5-c2-exclusions.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

Runtime extraction still accumulates exclusions until reset and only accepts
ordinary eval calls without row scripts. A cap replaces preceding reasons.
No narrowed extraction rule or yield improvement is claimed yet.

## Progress

- 2026-10-01: Read the Tcl proxy, assertion event consumer and pilot selection
  while C1's full regression ran. Recorded required observable outcomes and
  rejecting tests before implementation; frozen evidence remains unchanged.
