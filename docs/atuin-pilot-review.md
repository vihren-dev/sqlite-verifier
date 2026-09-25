# Atuin pilot: product-owner review

Status: DRAFT — implementation and proof evidence are still being integrated.
This document records the proposed meaning for review; it is not an approval or
a completed Step 1 pilot. The final review must identify the checked revision.

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

For a committed migration, the proposed requirements are:

- Keep every old history row and all its protected observations; introduce no
  additional history rows.
- Add `shell TEXT`, with NULL on every old row.
- Retain old declarations, NOT NULL constraints, primary/unique keys and indexes.
- Retain existing migration bookkeeping rows and insert the target's successful
  row with its version, description and checksum of the original migration SQL.
- Permit SQLite to update statistics rows, while retaining their definitions
  and preserving application history.

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
corruption and crash recovery. It does not certify Atuin synchronization,
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

The final packet must link the complete SQL/schema/profile, approved Lean
requirements and interpretation, proposed interpretation, proof, gate result,
adversarial results and installed-package result. Until then, approval is pending.
Existing synthetic examples also need a review record for their equivalent
source-syntax changes and replacement baseline hashes.

| Activity | Current evidence |
| --- | --- |
| Project and migration selection | Product owner selected Atuin and authorized the support extension. |
| Requirements/proof implementation | Agent work; final checked bundle pending. |
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
