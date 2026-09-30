# ADR 0005 C0 status

Created 2026-09-30. Status: IN PROGRESS.
Task: [outputs and parameters](20260930-adr5-c0-outputs.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C0 is open. Existing native evidence already records typed result rows, but not
parameter bindings, empty-result shape, direct counts or ordering evidence.
The structural adapter emits only v1 state observations; the Lean comparator
has no output observations. C1 owns deterministic clocks and profile setup.

## Progress

- 2026-09-30: Read native connection/recording, corpus replay, structural codecs,
  test harness and Nix boundaries. Recorded full package outcomes and its
  behavioral verification before editing source.
