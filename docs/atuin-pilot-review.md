# Atuin pilot: product-owner review

Status: READY FOR OWNER REVIEW — the formal certificate, complete local checks
and installed macOS runtime pass. Atuin publication and hosted platform checks
remain pending the baseline review. This document records proposed meaning, not
owner approval or a completed Step 1 pilot.

## Migration and logical meaning

The selected upstream revision is
[`5b10eb09c664d316b7384210399b02e6127f4027`](https://github.com/atuinsh/atuin/tree/5b10eb09c664d316b7384210399b02e6127f4027).
Its unchanged [shell migration](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260709214605_shell.sql)
is `alter table history add column shell text;`.

The logical model protects every existing history row's physical SQLite rowid
and every old stored field: `id`, `timestamp`, `duration`, `exit`, `command`,
`cwd`, `session`, `hostname`, `deleted_at`, `author`, and `intent`. The stored
`id` is separate from physical rowid. Empty histories are admitted; nonempty
histories are not excluded, and TEXT primary keys are not assumed non-NULL.
Existing legal storage classes and byte values must survive unchanged.

For a committed migration, the proposed application requirements are:

- Keep every old history row and all its protected observations; introduce no
  additional history rows.
- Add `shell TEXT`, with NULL on every old row.
- Retain old declarations, NOT NULL constraints, primary/unique keys and indexes.

The sealed runner profile additionally retains existing migration bookkeeping
rows and inserts the target's successful row with its version, description and
checksum of the original SQL. It permits statistics rows to change while
retaining their definitions. These guarantees belong to the execution profile;
`Requirements.contract` protects history, NULL extension and the exact schema.

The two statistics tables are part of the complete ten-object persisted schema.
They are not removed to simplify the input. The native capture is documented in
[Atuin capture](atuin-capture.md).

## Applicability and failure meaning

The proposed profile binds SQLite 3.46.0, SQLx 0.9.0, the captured fixed connection
configuration and the immutable migration catalog. The six preceding migrations
must already be recorded successfully with matching checksums, and the selected
target must still be pending. Those are explicit admission obligations in the
requirements and proof, not facts inferred from the schema alone.

The complete schema must match the supported captured definitions. The execution
profile excludes concurrent application writers, external schema changes,
resource exhaustion, interruptions, I/O faults, corruption and crash recovery.
It does not certify Atuin synchronization,
encrypted record storage or every application query.

Before commit, a modeled failure leaves the original application history and
bookkeeping. After commit, a timing-update or later runner error can leave the
new column and successful bookkeeping row in place. Both cases must preserve
the old history observations. A reported runner error therefore does not imply
that the migration was unapplied. Closing the connection may maintain statistics.

`VERIFIED` will mean that the exact supplied artifacts satisfy this modeled
contract for every admitted state and modeled outcome. It will not mean that
the native migration was executed by the verifier or that it cannot return an
error. Native tests support the correspondence argument; they do not constitute
a proof of the SQLite C implementation or SQLx itself.

## Review and effort record

The proposed artifact set is inspectable:

- [Complete starting schema](../examples/atuin/schema.sql),
  [unchanged migration](../examples/atuin/migration.sql) and
  [execution profile](../examples/atuin/profile.json).
- [Application requirements](../examples/atuin/approved/Requirements.lean),
  [current interpretation and readiness](../examples/atuin/approved/Interpretation.lean),
  [complete schema](../examples/atuin/approved/AtuinSchema.lean) and
  [migration catalog](../examples/atuin/approved/AtuinCatalog.lean).
- [Proposed result interpretation](../examples/atuin/NextInterpretation.lean),
  [universal certificate](../examples/atuin/Proofs.lean) and
  [empty/nonempty readiness witnesses](../examples/atuin/AtuinWitness.lean).
- [Four-source hash map](../examples/atuin/approved/baseline.json), proposed for
  approval; the directory name `approved` does not record human acceptance.
- [Three payload comparisons](atuin-model-conformance.md),
  [two complete runner traces](atuin-runner-conformance.md) and
  [seven public CLI checks](../tests/atuin_cli_test.py).

The certificate at formal revision `1c3f167d` and source CLI unit `0bd91b4d`
pass independent review. The universal theorem and independent kernel gate use
only `propext`, `Classical.choice` and `Quot.sound`. The unchanged input verifies;
changed column, omitted primary key, changed prior checksum, omitted old field,
changed approved helper and unfinished proof all reject for their intended
reasons. The actual macOS archive also passes all seven cases after offline
installation under an isolated, poisoned ambient environment, alongside the
existing positive/refuted/unsupported package checks. Its local log is
`build/atuin-installed-package.log` (exit 0). The final combined `just check`
also passes (`build/atuin-complete-check.log`, exit 0), including three payload
and two runner/model comparisons, the adversarial gate and all CLI regressions.
A retained actual `VERIFIED` response and compiled input closure are at
`build/atuin-pilot-review.json` and `build/atuin-pilot-review/`. Hosted Atuin
platform results remain pending; the packaging recipe repeats the installed
checks on each platform after publication is authorized.

The two existing sets of synthetic requirements also replace positional records with named fields to
compile against the richer schema type; their intended observations and failure
policies are unchanged. Their replacement source hashes are in
[the ordinary baseline](../examples/approved/baseline.json) and
[the allowed-failure baseline](../examples/allowed_failure/approved/baseline.json).
Approval must cover those source changes too; the baseline gate is not bypassed
merely because the examples compile.

| Activity | Current evidence |
| --- | --- |
| Project and migration selection | Product owner selected Atuin and authorized the support extension. |
| Requirements/proof implementation | Agent work; arbitrary-data proof and seven source CLI cases checked. |
| Human requirements authoring or adaptation | Not yet measured. |
| Human repair of a rejected case using diagnostics | Not yet demonstrated or measured. |
| Human requirements and proof review | Pending. |
| Previous workflow and comparative effort | Not supplied; no time saving is claimed. |
| Atuin upstream adoption or endorsement | Not claimed. |

After the engineering evidence is complete, the owner reviews the protected
observations, admission conditions and failure policy, and records any changes.
The pilot session must also exercise a requirements adaptation and diagnosis of
a rejected example. Record actual human authoring, repair and review effort
separately from agent work. Product acceptance and a roadmap update are still
required before Step 1 may be marked DONE.
