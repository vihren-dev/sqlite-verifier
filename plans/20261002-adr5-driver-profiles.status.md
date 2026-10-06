# ADR 0005 measured driver profile gaps: progress

Created 2026-10-02. Status: DONE, verified 2026-10-02.
Task: [driver profile outcomes](20261002-adr5-driver-profiles.task.md).
Specs: [ADR 0005 §3.2](../docs/adr-0005-conformance-corpus-scale.md#32-execution-profiles),
[execution profiles](../docs/execution-profile.md), and
[workload commands](../docs/conformance-workload.md).
Dependency: [C7 replay gates](20261002-adr5-c7-replay.status.md), DONE at `cf6657b1`.

## Current state

Core native evidence supports source-pinned SQLite 3.51.0, 3.46.0 and the
additional native-only 3.53.4 build. Old pins and default identities are unchanged.
Format-2 profiles explicitly establish trusted schema, DQS_DML, DQS_DDL and
actual read-only/read-write access, with settings and access readback on case,
fixture, reopened and committed-state connections. Fixture initialization is
separate from read-only case execution. The effective column limit remains 2000.
Old profile bytes, native versions 1–4 and frozen corpora remain compatible.

Both platform builds verify the official archive/source identity and retain all
39 actual compile options, including the compiler identity. The independent
recorder build remains distinct from an application's exact driver build.
Source mismatch alone is not proof of changed SQL behavior. External
compile-option and platform dispositions remain necessary before a truthful
workload comparison can complete.

Existing frozen records and profiles must retain their behavior and exact
stored identities. New native evidence does not expand production semantics,
the public proof profile CLI or the admitted correspondence boundary. C7's
completion and external workload completion remain separate gates.

## Relevant sources

`nix/sqlite.nix`, `nix/flake.nix`, `build-support/{default,tests}.nix`,
`conformance/{native_library,native_connection,execution_profile,native_record,
native_acquisition,native_statements,corpus,corpus_shards,native_replay,workload,workload_inputs}.py`,
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
  infrastructure needs after C7 completed at `cf6657b1`. This internal review
  does not constitute an owner decision about a production profile. Additional
  source pinning is an explicit implementation decision, not a claim of observed cross-version
  inequality or exact-driver-build equivalence. Old profile compatibility,
  read-only fixture lifecycle and scoped error handling are required outcomes.
  Document checks passed (2 tests). This preparation is committed before code;
  implementation and the actual workload gate remain open.

- 2026-10-02: Implemented the additional independent pin and profile-only
  transport format 2. Existing named identity versions and native/storage
  versions remain separate. Extracted the existing acquisition opening and
  authorizer into `native_acquisition.py`; every authored Python file stays below
  200 lines. Fixture initialization changes only access mode, verifies settings
  before each reopen and completion, then closes before actual read-only opening.
  Committed observers verify the same applicable settings. Only exact READONLY
  code 8 under a verified read-only profile becomes statement evidence; all
  extended recovery/filesystem variants remain harness errors. Public directory
  checks preserve typed reads, final write denial, exact manifest profile binding,
  fresh replay and refusal of unreached SQL. Model admission is unchanged.

- 2026-10-02: Verified the official archive SHA256 and published source SHA3,
  actual engine/source ID, complete options, column limit and access behavior on
  `aarch64-darwin` and `x86_64-linux`. Old native derivation identities are exact
  before/after matches on both platforms. Measurements:
  [Darwin](../reports/20261002-adr5-driver-native-darwin.json) and
  [Linux](../reports/20261002-adr5-driver-native-linux.json).
  Independent lifecycle/transport review found no remaining blocker.

- 2026-10-02: Final verification passed. Focused profiles/context/storage:
  44 tests on Darwin (1.47 seconds) and Linux (4.95 seconds); full hermetic model:
  270 passed, one optional Tcl skip (242.64 seconds; the actual Tcl upstream
  target separately passed all 28). Fast hermetic replay: 12 passed on Darwin
  (13.26 seconds) and Linux (27.25 seconds). Actual `nix develop path:./nix
  --command just test`: 286 host cases plus 28 subtests, and all six development
  targets passed. Nix dependency/flake ownership/CI/document checks: 37 passed.
  The final added manifest-tamper check passed independently and in the rebuilt
  full model target. Resource guard passed after the owner's space cleanup.
  This public task is DONE; the external workload suite remains open.
