# ADR 0005 C1 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [verified profiles](20261001-adr5-c1-profiles.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

The default source-pinned native connection verifies DQS and column limits.
Evidence does not yet carry a complete versioned profile. Clock functions are
excluded by the acquisition authorizer; the new native clock primitive is not
yet integrated into recording/replay. C1 is
open; no claim of workload suite completion is made.

## Progress

- 2026-10-01: Read the profile contract, native library/connection/recording
  boundaries and existing profile documentation. Recorded observable outcomes
  and behavioral verification before implementation. No production semantics
  or frozen evidence changed.

- 2026-10-01: Added a private SQLite VFS copying the pinned engine's native
  filesystem callbacks and overriding both native time callbacks. Connections
  may select it explicitly through sqlite3_open_v2; the default VFS is unchanged.
  The clock validates Unix-millisecond inputs and keeps callbacks alive until
  explicit unregister after connection closure. Native tests prove defaults,
  trigger bodies and SELECT-only probes see two supplied times, and registration
  cleans up. Clock/record/DQS checks: 13 passed in 0.81 seconds. Profile identity,
  per-statement recording, replay and manifest binding remain open.
