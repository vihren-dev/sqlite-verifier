# Shared table shape

Created 2026-10-06. Status: IN PROGRESS. Resumed 2026-10-09 after T10 delivery.

T10 is delivered in PR #56. Resume from accepted main with the independent
Belay.Sqlite package and the in-process parser. The original partial
implementation remains a recoverable checkpoint; its old checks do not prove
acceptance of the resumed source.
Source: [public issue #15](https://github.com/vihren-dev/sqlite-verifier/issues/15).
Approved outcome: T07 in the product repository's
`plans/20261006-ready-task-proposal.md`.

## Observable outcomes

`Table` and `TableSchema` each contain one name-free `TableShape`, which owns
ordered column declarations and retained table properties. A stored table has
rows and a shape, with its name supplied only by the database key. The schema
entry retains its name. Neither type stores a second copy of shape fields.

`Conforms` compares the complete stored and declared shape as one value,
including absent-table behavior. Existing schema validity and stored-row validity
requirements retain their meaning. Changing any represented column or property
rejects conformance even when every row remains unchanged. Adding a future shape
field therefore makes it part of the same equality automatically.

Schema column and property lookups remain derived conveniences. A whole-shape
lookup is available as the primitive. No lookup has the obsolete legacy marker.
All production definitions, library proofs, examples, Atuin modules, conformance
observations, compiler fixtures and generated Lean inputs use the shared shape.
Replaced stored fields and implementation paths are removed without aliases.

Structural transport preserves all existing column metadata, primary keys,
unique keys, index identity/order/uniqueness, row order, physical rowids and
typed cell bytes. The current version-one flat table/schema wire format remains
the single encoding; decoding packs its metadata into the shared shape. The
frontend's generated `SchemaInputs` and `SqlInputs` agree with those decoded
kernel terms. Existing frozen corpus and historical receipt bytes remain intact.
Current model/native comparisons and example statuses retain their meanings.
This representation change adds no SQL capability or package/namespace rename.

Every changed public declaration and field has checked Verso documentation.
Propositions state their exact quantifiers, assumptions and vacuous cases;
reusable proofs state their strategy. Existing logical and execution formulas
retain their meaning except for the required whole-shape conformance equality.

## Acceptance suite

Bounded compiler tests establish valid shared shapes and reject column, default,
nullability, primary/unique key and index changes with identical rows. They also
cover missing tables, present empty tables, duplicate-name schema validity,
derived lookups and preservation after CREATE, ADD and row-only writes.

Structural codec tests use explicit version-one golden records with rich metadata
and exact typed cells. Round trips preserve those records; malformed metadata or
cells fail closed. Decoded generated inputs match freshly compiled frontend
modules, and both generated schema modules use the nested representation.
Existing five frozen structural cases and immutable v1–v5 corpus/receipt hashes
remain unchanged. Fresh emitted Lean regression terms compile against the new
library without depending on historical generated source.

All changed library and example proofs compile under the pinned Lean 4.34.1
toolchain without added axioms or `sorry`. Source checks, all currently configured ordinary suites,
affected native/model/law checks, complete model acceptance and actual offline
installed example/bundle tests run on both supported platforms. Current success,
checked-refutation and Atuin bundles retain their actual input/library identities,
trust bindings and deterministic repeated preparation. Nix source identity checks
cover any new module or test input. Every test has an explicit timeout.

Independent review follows the repository checklist. Final R8 owner review is
required for the changed model target and structural codec. T13 is delivered. Bounded affected checks do not replace complete model
acceptance. The task is DONE only after every required gate
passes. Publication, merge, release and issue closure require parent coordination.

## Constraints and relevant source

`Model.lean` defines the duplicated representation and current conformance;
`Declarations.lean` owns column/property metadata. `StructuralCodec.lean` serves
both the bundle checker and `VerifierConformance/Json.lean`. Python
`migration_check/structural.py` and `conformance/case_format.py` own their existing
flat encoding, while `migration_check/sql_model.py` emits Lean source.

`Library`, `SchemaExtension`, `SchemaPreservation`, `LiteralPreservation`,
`Preservation` and the demonstrations prove metadata and projection preservation.
Atuin uses generated sealed starting schema. Root-owned T15 application-key
helpers and their variant must be included in final caller assembly without
changing their logical contracts. Coordinate the authored-documentation inventory
and public walkthrough with the API-reference worker before final acceptance.

T10 is now a prerequisite under the latest owner review. On resumption, package
names and lookup ownership must follow its accepted and completed boundary.
Existing example behavior and frozen corpus bytes retain their meanings.
Current example source changes follow main’s test-fixture policy; final model
and codec owner review remains required.

## Accepted boundary at resumption, 2026-10-09

Model and codec changes belong to `packages/belay-sqlite/Belay/Sqlite`. Python
frontend changes belong to `belay/sqlite`; application Lean emission remains
in `migration_check`. Use the accepted in-process parser from PR #77. The
examples are test fixtures: main removed the protected approved-baseline check.
Frozen corpus bytes remain unchanged, and final model/codec owner review remains
required. Follow current AGENTS.md and ADR 0009: tests check our code and use
dependencies as oracles; do not restore removed dependency-output checks or
committed copies of validation result folders.
