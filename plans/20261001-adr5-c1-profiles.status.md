# ADR 0005 C1 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [verified profiles](20261001-adr5-c1-profiles.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

The default source-pinned native connection verifies DQS and column limits.
Evidence does not yet carry a complete versioned profile. Clock functions are
excluded by the acquisition authorizer; engine time is not controlled. C1 is
open; no claim of workload suite completion is made.

## Progress

- 2026-10-01: Read the profile contract, native library/connection/recording
  boundaries and existing profile documentation. Recorded observable outcomes
  and behavioral verification before implementation. No production semantics
  or frozen evidence changed.
