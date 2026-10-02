# ADR 0005: measured driver profile gaps

Created 2026-10-02. Status: DONE, verified 2026-10-02.
Status: [progress](20261002-adr5-driver-profiles.status.md).
Specs: [ADR 0005 §3.2](../docs/adr-0005-conformance-corpus-scale.md#32-execution-profiles),
[execution profiles](../docs/execution-profile.md), and
[external workload commands](../docs/conformance-workload.md).
This work follows the [C7 gates](20261002-adr5-c7-replay.task.md); it does not
replace the separate external workload completion gate.
Completion evidence and platform checks are recorded in the linked status file.

## Scope and decision

A measured application driver uses SQLite 3.53.4 with trusted schema disabled,
both DQS modes disabled, and read-only connections. The current recorder cannot
establish those conditions. This task adds the public native infrastructure
needed to record and compare those conditions truthfully. Workload names, SQL,
source identities, driver measurements and workload results remain external.

ADR 0005 conditionally requires another source pin when a measured engine
difference affects workload SQL. A source-version mismatch alone does not prove
such an effect. The additional decision here is to pin 3.53.4 for truthful
workload comparison rather than assert unmeasured cross-version equivalence.
An independently built native library is not automatically the exact driver
build, even when its release and source ID match.

## Observable outcomes

SQLite 3.53.4 is available as an additional source-pinned native evidence engine
on `aarch64-darwin` and `x86_64-linux`. Its source archive digest, release version
and full source ID are verified. The official
[3.53.4 release](https://sqlite.org/releaselog/3_53_4.html) identifies source ID
`2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`.
Existing native pins, production parser/version selection and default profiles
retain their identities and behavior. Selecting the additional native engine
does not add production model or proof support for that release.

New explicit native profiles identify trusted-schema behavior, DQS_DML,
DQS_DDL and database access mode alongside the existing full engine identity,
compile options, foreign keys, recursive triggers, transactions, clock and
other-writer assumptions. Each supported boolean and access combination is
established and read back on the actual case connection before case SQL runs.
Read-only access means SQLite opened the case database read-only; a SELECT-only
guard or `query_only` setting cannot substitute for that access mode.
Settings changed by case SQL are detected without resetting or normalizing
the evidence. Same-value writes remain permitted where already supported.

Schema and data fixtures can be initialized before a read-only case connection
is opened. Fixture initialization does not grant the case write permission or
insert application statements. Initial, visible and persisted observations,
typed parameters, statement outputs, clock inputs and transaction state retain
their existing meanings. Committed-state observers and reopened connections
verify their applicable settings and engine identity too.

An intentional write attempted through a verified read-only case connection
records SQLite's primary and extended READONLY result, stops at the first
statement error, and survives store/load/fresh native replay. Missing files,
open failures, unexpected permissions, I/O, locking, journal/recovery failures
and resource exhaustion remain harness failures. A READONLY primary code alone
cannot turn environmental extended-result failures into semantic evidence.
An intentional final failed statement can complete an inventory; unreached SQL,
parameters or clock inputs still cause the workload completion check to refuse it.

Profile transport has explicit supported field sets and versioned identity.
Frozen old profile bytes and native record versions 1–4 remain loadable and
replayable with their original settings, including trusted schema on, DQS on
and read-write access for the existing implicit/default profiles. New fields
cannot silently reinterpret old evidence or force rewriting any frozen corpus,
synthetic input, historical report or approved production profile. Exact manifest
profile matching and native replay mismatch refusal remain in force. Profile,
case, native acquisition and snapshot storage versions stay separate.

Actual native compile options are retained completely for each engine build;
they are not stripped or relabelled to resemble a driver. External comparison
evidence accounts for each driver/native compile-option difference with its
measurement, disposition, rationale and relevant SQL evidence. A difference
can be declared immaterial only for the assessed scope; unresolved behavioral
or runtime-limit differences remain explicit gaps. Private evidence and these
dispositions remain with the external workload. Adding this native pin alone
does not complete the workload gate or claim exact-driver-build equivalence.

`record_sql` remains a flexible primitive. External directory commands use the
same validated profile establishment, recording and replay boundary. Valid
new-profile evidence remains explicitly `MODEL_UNSUPPORTED` unless an existing
production capability genuinely admits it; native success cannot become model
agreement or kernel correspondence by itself.

## Behavioral verification

Bounded native tests on both supported platforms verify the additional engine's
actual version, source ID and compile options, refusal of changed identities,
and explicit trusted-schema/DQS/access readback. Neutral fixtures exercise the
two DQS modes independently, preserving resolved quoted identifiers while
showing the native behavior of double-quoted literals under each setting.
Trusted-schema tests verify both settings and refuse a changed or unestablishable
condition; any behavior fixture uses measured SQLite behavior within the
recorder's supported callback/extension boundary.

End-to-end generic directory tests initialize a fixture, record read-only SELECT
outputs with typed parameters, retain an intentional final READONLY write
failure, freeze its shard, load it through the ordinary loader and replay it
fresh under the exact new profile. Changed profile settings, access mode,
engine identity, manifest declaration or bound input fail. Read-only failure
tests distinguish ordinary SQL denial from environmental failures, including
extended READONLY conditions. Incomplete inventories remain refused.

Legacy compatibility checks replay representative native versions 1–4 and old
explicit profiles with unchanged observations, alongside the frozen corpus
compatibility gates. New profile transport rejects malformed values, unsupported
field/version combinations and booleans used as version numbers. Existing
clock, parameter, probe-safety, profile-mismatch, full model and document checks
continue to pass. Every test and native statement has a configured timeout.

## Tricky points and relevant sources

`nix/sqlite.nix` owns independent native source builds; the development shell,
Nix checks and library resolver must expose the additional engine consistently
without replacing the default engine. Cross-platform compiler and compile-option
identity remain measured facts. No private driver dependency belongs in core CI.

`native_library.py` validates source pins and declares C signatures.
`native_connection.py` currently opens with READWRITE|CREATE, hardcodes trusted
schema on, verifies library-default DQS=1, and fixes the column limit at 2000.
`execution_profile.py` has a strict old field set and no access/trusted/DQS fields.
The measured effective limit remains a precondition; this task cannot infer a
driver's runtime limit from its compile-time ceiling.

`native_record.py` creates fixture and committed-state connections and supports
reopen/configuration setup operations. Its lifecycle must separate fixture
initialization from read-only case execution without hiding errors or changing
recorded setup meaning. `native_statements.py` and `native_connection.SQL_ERRORS`
separate statement evidence from environmental failures; extending the error
boundary requires the actual connection conditions and extended result code.

`corpus.py`, `corpus_shards.py`, `workload.py`, `workload_inputs.py` and
`native_replay.py` bind formats, exact profiles and fresh observations. The
production profile CLI and model capability boundary are separate. Existing
frozen compatibility is required by ADR 0005, even though new acquisition may
use a richer profile transport.
