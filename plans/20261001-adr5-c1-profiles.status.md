# ADR 0005 C1 status

Created 2026-10-01. Status: DONE 2026-10-01.
Task: [verified profiles](20261001-adr5-c1-profiles.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

The default source-pinned native connection verifies DQS and column limits.
Native acquisition v4 carries a validated explicit profile and clock inputs.
Recording and fresh replay establish the same conditions and engine clock.
Profile manifests bind v4 cases to exact declarations. The final contract audit
passes; C1 is done. Later core packages and the workload suite remain incomplete.

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

- 2026-10-01: Added an immutable execution-profile record measured from the
  running engine's version, source ID and complete sorted compile options.
  Establishment refuses an engine mismatch or active transaction, sets foreign
  keys/recursive triggers and verifies native readback. Profile conditions name
  transaction and clock conventions; only implemented convention values are
  accepted. Native tests verify FK cascades inside BEGIN IMMEDIATE, identity
  mismatches and invalid conventions. Profile/clock/record/DQS checks: 14 passed
  in 0.79 seconds. These primitives still require wire decoding and integration
  into acquisition, replay and manifests; model admission must remain separate.

- 2026-10-01: Added strict profile JSON transport and native acquisition v4.
  Recorder/replay establish profiles on writer and reader; controlled profiles
  require a setup clock and one clock per reached statement, retained through
  native probes. SQL cannot change established behavioral settings or use a
  different BEGIN mode. Fresh replay refuses another profile. Clock defaults,
  triggers, RETURNING and an ordered probe replay identically at a later wall
  time. Malformed profiles/clocks remain harness errors; valid explicit profiles
  stay model-unsupported until production profile capability exists. Documented
  measurement of each running workload driver's version/source/options. Full
  pinned hermetic suite: 69 passed in 128.14 seconds; document checks: 2 passed.
  Frozen v1–v3 evidence remains unchanged. Manifest binding and final C1 audit
  remain open.

- 2026-10-01: Corpus loading validates full executionProfiles manifest records.
  Each v4 case must match exactly; missing/conflicting declarations and duplicate
  name/version identities are refused. Digest binding still covers all native
  case contents, including profiles and clocks. Temp-directory native corpus
  tests exercise success and refusals; legacy frozen upstream replay is retained.
  Profile/upstream/docs checks: 8 passed in 4.95 seconds; final docs: 2 passed.
  C1 remains open for the final contract audit.

- 2026-10-01: Final audit added explicit UTC timezone control/restoration for
  native localtime conversion, refused unsupported behavioral setting PRAGMAs,
  and selected the profile's engine from either existing native pin. Tests
  replay under different caller timezones and verify source identity/replay on
  SQLite 3.46.0. Full pinned hermetic suite: 70 passed in 129.13 seconds;
  focused profile/record/docs: 15 passed; document checks: 2 passed. C1 DONE.

## Completion evidence

- Profile/manifest identity and mismatch refusal: execution_profile.py,
  corpus.load/native_replay and conformance_profile_test.py.
- FK-on and immediate transactions: native setting readback and cascade test,
  plus profiled recording/replay with enforced BEGIN convention.
- Different-wall-time clock replay, defaults/triggers/probes and timezone:
  conformance_clock_test.py and conformance_profile_test.py.
- Driver measurement method: docs/execution-profile.md.
- Legacy format/profile compatibility: full hermetic frozen replay regressions.
