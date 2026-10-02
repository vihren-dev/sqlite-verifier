# ADR 0005 measured driver profile gaps: progress

Created 2026-10-02. Status: PREPARED; implementation has not started.
Task: [driver profile outcomes](20261002-adr5-driver-profiles.task.md).
Specs: [ADR 0005 §3.2](../docs/adr-0005-conformance-corpus-scale.md#32-execution-profiles),
[execution profiles](../docs/execution-profile.md), and
[workload commands](../docs/conformance-workload.md).
Dependency: [C7 replay gates](20261002-adr5-c7-replay.status.md), DONE at `cf6657b1`.

## Current state

Core native evidence supports source-pinned SQLite 3.51.0 and 3.46.0.
Connections currently open read-write/create, establish trusted schema on,
verify DQS_DML=1 and DQS_DDL=1, and establish an effective column limit of 2000.
Explicit profiles identify engine/source/complete compile options and existing
behavioral settings, but do not carry trusted-schema, DQS or access-mode fields.
Native replay and external directory loading already bind exact profile identity.

An additional 3.53.4 native pin and explicit connection conditions are the
authorized public scope. The release/source identity is published by SQLite;
the independent recorder build remains distinct from an application's exact
driver build. Source mismatch alone is not an ADR mandate or proof of changed
SQL behavior. External measurement-based compile-option dispositions remain
private and are necessary before a truthful workload comparison can complete.

Existing frozen records and profiles must retain their behavior and exact
stored identities. New native evidence does not expand production semantics,
the public proof profile CLI or the admitted correspondence boundary. C7's
completion and external workload completion remain separate gates.

## Relevant sources

`nix/sqlite.nix`, `nix/flake.nix`, `build-support/{default,tests}.nix`,
`conformance/{native_library,native_connection,execution_profile,native_record,
native_statements,corpus,corpus_shards,native_replay,workload,workload_inputs}.py`,
and existing native profile, storage and external directory tests.

## Progress

- 2026-10-02: Read the accepted ADR, execution-profile/workload documentation
  and current connection, acquisition, replay and pin code. Prepared observable
  outcomes and public end-to-end checks before implementation. Verified that
  SQLite publishes release 3.53.4 and its source ID. No governing contradiction
  or unmentioned implementation requirement was found. Read-only fixture
  lifecycle, old profile transport compatibility and scoped READONLY error
  classification are explicit task constraints. No engine build, implementation,
  driver-equivalence claim or workload acquisition was performed.

- 2026-10-02: Root reviewed the prepared scope against the accepted ADR and
  measured gaps after C7 completed at `cf6657b1`. Additional source pinning is
  an explicit implementation decision, not a claim of observed cross-version
  inequality or exact-driver-build equivalence. Old profile compatibility,
  read-only fixture lifecycle and scoped error handling are required outcomes.
  Document checks passed (2 tests). This preparation is committed before code;
  implementation and the actual workload gate remain open.
