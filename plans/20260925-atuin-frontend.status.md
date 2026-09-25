# Atuin frontend integration status

Created: 2026-09-25. Status: IN PROGRESS — not DONE.
Task: [unchanged Atuin migration](20260925-atuin-shell-migration.task.md).

The technical lead supplied the stable schema representation before implementation:
Column declared-type/nullability/default metadata; TableProperties primary keys,
unique keys and explicit indexes. The frontend emits named Lean records and keeps
rich admission confined to declarative baseline schemas. Migration ADD remains
canonical, nullable and defaultless. CREATE against a baseline containing
constraints or indexes rejects until that execution namespace is modeled.

Current source: `migration_check/{sql_model,schema_syntax,schema_translate,translate}.py`.
Checks: `tests/test_schema_translation.py` plus existing translation regressions.
Six real-parser tests passed in 0.261 seconds. The full real SQLx capture from
conformance translates, and its predicted ADD result equals the captured next
schema using the existing 3.51 grammar. This is not yet 3.46 parser evidence or
kernel acceptance; versioned native parser and formal definitions are in progress
in the other workspaces. No verified pilot claim is made.

Selected-parser plumbing now maps 3.46.0 to its distinct binary and checks its
reported profile; 3.51.0 remains the default. All 15 fast discovery tests passed
in 2.799 seconds under pinned Nix with 30-second outer timeout. An initial
unpinned invocation failed environment assertions/outer-sandbox permissions;
the correctly configured run passed without test or production relaxations.

Pending: formal emission compilation; stable execution-profile/VC interface;
selected-parser plumbing; equivalent existing Lean fixture syntax and protected
baseline digest changes; independent review and end-to-end checks.

## Continued checked integration

Rebased onto formal schema revisions `d194b93f`/`390ac88d` and root native-parser
checkpoint `820370f9`. Both real parser binaries build. Rich named schema emission
compiled and its metadata checks passed Lean's kernel before profile extension.
Existing CLI positive/refuted/allowed-failure/adversarial cases passed after
syntax-only named-record updates to example requirements/interpretations and
native/model expected literals. Matching protected baseline digests were updated;
this does not silently approve changed application meaning.

The conformance capture was corrected to close/reopen the real pool between
migrations, exposing `sqlite_stat1` and `sqlite_stat4`. The original eight-object
observation was an in-run snapshot, not the complete persisted baseline. Admission
now retains only the exact engine-defined statistics shapes and their untyped
columns; arbitrary reserved tables, altered statistics definitions and migration
targets still reject. Independent conformance source/adversarial review accepted
the structural schema admission.

Execution-profile input now validates the lead's exact JSON kind, signed versions,
strict prior ordering and SHA-384 catalog checksums. Target checksum is calculated
from original migration bytes. The profile and manifest digest are bound separately
in generated inputs/inspection output. Formal profile datatypes and gate changes
remain lead-owned and pending integration. All 19 fast tests passed in 2.947 seconds
under pinned Nix with a 30-second outer limit.

One existing native/model case (`limit_before_duplicate`, 2,000 columns) exceeded
its unchanged 30-second Lean child limit after richer records. Compact emission
now omits default fields; focused compile-cost investigation is in progress.
No timeout increase or failing-check suppression has been introduced.

The compile-cost issue is resolved without increasing timeouts: plain columns omit
redundant default fields and a structurally unchanged resulting schema references
`startSchema`. The actual full five-case native/model suite and false-empty-target
rejection passed with their original 30-second child limit. The new standalone
`schema_generation_test.py` passed both grammar versions and kernel-checked rich
records and the SQLx profile against committed formal revision `66a8e381`.
The complete persisted four-table baseline also matches the captured after-schema
through the actual 3.46 parser and unchanged migration.

Independent conformance review accepted the current schema/profile admission,
reproduced seven focused tests, and checked 28 additional negative CST cases on
each native parser. No actionable finding remained. A new CLI regression requires
an existing CREATE-containing autocommit example to reject as UNSUPPORTED under
the ADD-only SQLx profile; its final run
awaits the lead-owned profile-aware VC/gate integration. This working unit must
not be published as SQLx verification before that binding is integrated.

## First checkpoint boundary

The first checked commit intentionally contains schema translation, typed profile
parsing/emission, runtime parser-selection support and equivalent fixture syntax.
Its public CLI remains **SQLite 3.51.0 only**. Profile-aware CLI acceptance,
associated public documentation and the new CLI scope test remain a separate
working change until the lead's VC/gate binding is integrated. Generic generated
data is not a verification verdict. Root will not publish this intermediate unit
as completed SQLx verification.

A primary-source SQLx finding adds an exact original-byte prefix check: SQLx
`sql.starts_with("-- no-transaction")` opts out of transactions. The atomic profile
rejects that exact prefix; it does not trim or case-fold the input. Focused tests
also preserve the upstream whitespace/case distinction. Root and lead accepted
the split boundary so conformance can consume an immutable frontend checkpoint.

Final first-checkpoint validation: `nix develop --command timeout 30 python3 -m
unittest discover -s tests -p 'test_*.py'` passed all 19 tests in 3.193 seconds.
The bounded real CLI suite again passed positive, checked-refutation,
allowed-failure and adversarial cases with the equivalent approved fixture
syntax. Rich schema/profile emission and all five native/model cases had passed
against the same committed formal interfaces. No required failing check remains
for this data-only checkpoint; profile-aware verdicts remain the next unit.

## Profile-aware CLI integration

Integrated lead revision `8ca23cd5`, which binds `Generated.profile` in both the
convenience target and independent gate and models explicit readiness plus staged
SQLx outcomes. The CLI now selects the parser from the validated profile, supplies
original SQL bytes for the target checksum/directive check, and records the exact
manifest digest. New CLI regressions require unsupported SQLx CREATE and the
exact no-transaction directive to reject before proof compilation. The existing
seven input categories are unchanged. Final integration checks are running;
actual Atuin proof artifacts and owner review remain separate pending work.

The integrated profile-aware build passed all 21 Lean/checker jobs. The full CLI
suite passed with legacy verification/refutation/allowed-failure behavior plus
SQLx scope/directive rejection. The full kernel-gate suite passed, including
changed protected profile and forged convenience target attacks. The standalone
both-parser schema/profile generation check also passed against this final API.
Bounds remain 600 seconds for CLI, 360 for the gate suite, 75 for generated-schema
checks, with unchanged bounded child processes. No timeout was raised for this
unit. Positive verification of the actual Atuin bundle awaits the lead-authored
proof and subsequent owner contract review; these engineering checks do not
substitute for either.
