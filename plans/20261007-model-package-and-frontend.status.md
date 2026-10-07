# Status: T10 model package and SQL frontend

Created 2026-10-07. Status: IN PROGRESS.
Audience: team and reviewers.
Task: [task](20261007-model-package-and-frontend.task.md).
Specification: [accepted ADR 0006](../docs/adr-0006-model-boundary-and-execution-levels.md).
Source: [issue #31](https://github.com/vihren-dev/sqlite-verifier/issues/31).

## Current checkpoint

The owner-approved T10 card and accepted ADR define the package boundary.
The first structural refactor separates model facts from application helpers.
The standalone model package builds independently. The Python frontend now
lives in `belay.sqlite`; its source and sandbox checks pass. Application model
integration and the two trusted compiled roots remain incomplete.

The accepted ADR was delivered through
[PR44](https://github.com/vihren-dev/sqlite-verifier/pull/44), normal merge
`b91e5cb5b3e145bc9713cc5e2b88bd502aa9ad0a`. The approved exporter in
[PR47](https://github.com/vihren-dev/sqlite-verifier/pull/47) and single executor
in [PR48](https://github.com/vihren-dev/sqlite-verifier/pull/48) are also delivered.
Implementation uses reviewed main `eb061e76`. Held T07, T15 and T18b source
or receipts are not accepted inputs.

## Relevant specifications and source

- ADR 0006 was accepted on 2026-10-07 with `Belay.Sqlite`, Lake package
  `belaySqlite` at `packages/belay-sqlite/`, a separate codec and Python import
  `belay.sqlite`. The parent `belay/` has no initializer and only its `sqlite/`
  child initially. The leaf initializer and other distributions' namespace
  portions remain outside that parent-layout restriction.
- [Lake configuration](../lakefile.toml), [model](../SqliteVerifier/Model.lean),
  [library](../SqliteVerifier/Library.lean),
  [nullable projection](../SqliteVerifier/NullableProjection.lean),
  [codec](../StructuralCodec.lean) and
  [conformance laws](../VerifierConformance/Laws.lean) show current ownership
  edges. Both schema lookups are structural dependencies of `Conforms`.
- [Frontend types and emission](../belay/sqlite/sql_model.py),
  [parser](../belay/sqlite/sql_tree.py),
  [translation](../belay/sqlite/translate.py),
  [records](../belay/sqlite/structural.py) and
  [inputs](../migration_check/inputs.py) show the shared-record boundary.
  Current type methods, profiles and values also emit Lean text; neutral errors
  currently share application diagnostics. These edges need explicit ownership.
- [Source selection](../build-support/sources.nix),
  [Nix builds](../build-support/default.nix),
  [runtime assembly](../build-support/runtime.nix),
  [test targets](../build-support/tests.nix),
  [source identity checks](../tests/test_source_identity.py),
  [runtime fixtures](../tests/runtime_fixtures.py) and
  [CI scope](../tests/ci_scope.py) assume one package root.
- [Runtime discovery](../migration_check/runtime.py),
  [source resolution](../migration_check/source_closure.py),
  [preparation](../migration_check/prepare.py),
  [stage identity](../migration_check/stage_store.py),
  [kernel gate](../ProofChecker.lean) and
  [bundle gate](../BundleChecker.lean) need one consistent pair of installed
  library roots with exact module origins and unchanged stage isolation.

## Progress

Planning and acceptance were prepared before code at `9458fc52`, with reviewed
exporter `07dc71b3` and executor `45ac63b2` as audit inputs. All 67 initial
local references resolved. The accepted ADR fixes the package names and leaves
the Python leaf initializer choice open. The structural ownership and frontend
dependency findings below remain the migration constraints. Dependency delivery
then establishes main `eb061e76` as the implementation base.

## Read-only ownership audit

The audit uses accepted ADR0006 and approved executor source `45ac63b2`, with
exporter source `07dc71b3`. Fifty declarations were inventoried across the six
mixed Lean files and the adjacent `SqlProofs` and `ContractProofs` files.
The smallest ownership split is:

| Current module | Model declarations | Application declarations |
| --- | --- | --- |
| `Library` | `Covers`, `Schema.emptyDatabase_conforms`, `Conforms.table`, `Table.Valid.appendColumns`, `Conforms.set`, `Database.set_comm`, `TableExtends.covers`, `TableExtends.project` | `LogicalRows`, `observeTable`, `projectedInterpretation`, `unreachableFailures` and both interpretation/failure soundness wrappers |
| `LiteralPreservation` | All eight declarations: row replacement, rowid maximum/freshness, inserted-table validity, key uniqueness, constraints and comparison readiness | None |
| `SchemaExtension` | `Schema.appendAt`, `Schema.lookup_appendAt`, `Schema.properties_appendAt`, `Conforms.appendAt` | None |
| `SchemaPreservation` | `Conforms.properties`, both structural `TableExtends` facts, `Table.KeysValid`, `TableExtends.keysValid`, `TableExtends.columnInvariant` | None; predicate parameters use the structural projection type instead of `LogicalRows` |
| `NullableProjection` | `nullExtension`, `Table.project_newNullable`, using the structural projection type | `NullableView`, `observeNullable` |
| `Laws` | `nonControl`, `SuccessfulBody`, `body_rollback`, `rollback`, `literal_cases`, `statement_atomicity`, `add_column_shape` | None; runner and observation transport stay test-owned |
| `SqlProofs` | Its four SQL-only guard and composition declarations | None |
| `ContractProofs` | None | Both `VerificationConditions` helpers and `violates_required_schema` |

`Schema.lookup` and `Schema.lookupProperties` stay with `Conforms` in the
model. The current `Laws` file does not use its `NullableProjection` import.
Removing that edge and extracting the structural nullable theorem avoids a
contract dependency without changing a formula. Existing row-width, freshness,
support and idle-state hypotheses remain intact. T11 owns executor categories.

The 12 audited Python boundary files are byte-identical in architecture source
and approved executor source. Their concrete dependency edges are:

- Frontend-owned code comprises parser trees and invocation, translation,
  schema syntax, schema translation, literal DML, admission, raw model types,
  schema transition, literal parsing, profile selection and structural records.
- `sql_model` mixes those raw types with `.lean()` methods, `lean_string`,
  `lean_names`, `schema_inputs` and `sql_inputs`. `sql_values.lean_value` and
  `ExecutionProfile.lean` are emission edges. Application `Generated` emission
  stays outside the frontend; a small shared literal transport helper, if
  required by both consumers, must also be independent of application policy.
- `structural.generated_inputs_wire` currently derives a profile wire tag by
  stripping the dot from `profile.lean()`. Structural encoding must use the
  existing wire tag directly, independent of Lean generation. Schema emission
  preserves declaration-order indexes; native conformance uses canonical order.
- `sql_model` imports `sql_values`, which imports parser trees. The raw
  `SqlValue` type can reside with raw model types instead of bringing parser
  I/O into type and record imports. Existing lazy translator imports also need
  care when emission and validation acquire different owners.
- Frontend errors need their SQL status and source-span payload independent
  of `migration_check.diagnostics`. Application boundaries preserve the same
  external refusal statuses; application proof/runtime errors remain there.
  A frontend import or alias of the application exception would retain the edge.
- `sql_inputs` currently performs migration and write admission as a side
  effect. `native_replay` and `native_trace` discard its generated text. Their
  replacements must call the same frontend admission directly, before model
  comparison or native execution. Moving emission must not remove these checks.
- `inputs.generated_inputs` remains application orchestration: it consumes
  argparse options, discovers the runtime, hashes source SQL, rejects an empty
  migration and combines Lean emission with the same structural record.
  Conformance's `model_assertions` needs only inert string quoting, not this
  application generator. Its proof/observation transport remains test-owned.

Critical Lean callers include the invoice interpretation/proof roles, Atuin's
`AtuinFacts` and `AtuinWitness`, demonstrations, conformance outputs/JSON/laws,
codec consumers and both gates. Python callers include `case_format`, replay,
native tracing, metadata, generated programs, state-machine tests and all
frontend/generation/parity fixtures. Source extraction in mutation/coverage
harnesses, axiom-output assertions in `conformance_laws_test`, Nix input lists,
runtime roots and CI scope also embed old paths or names. A retained conformance
adapter with its own `table_wire` responsibility is not an old frontend alias.

The read-only inventory and byte comparisons passed under 15-second bounds.
No implementation check, build or native run was performed. No specification
contradiction was found; the accepted ADR already resolves lookup ownership and
the broad naming proposals. This findings checkpoint changes only this status
file. T09's completed plans, feature bookmark and raw review row stay unchanged.

## Remaining acceptance and open issues

Structural source compilation passes. Package/frontend migration, both native
platform gates, independent reviews, R8 final owner review and repository
delivery remain. T10 and #31 are not DONE.

#23's execution changes, #15's table shape, #18's validity and #27/#28 renames
remain separate. Report environment or specification blockers under workspace rules.

## Delivered implementation base

All dependency PRs are normally merged. PR #48 delivers reviewed executor
source as main `eb061e7655b10b9de03e43bd321f5b76bf1e7183`; its tree exactly
matches checked head `b8eb25dd`. The old architecture workspace and its audit
remain at `t10-planning-audit-20261007`. This workspace starts directly from
the delivered main and restores only this task and status. No held feature
history is merged. The accepted nine-suite layout and frontend import checks
are part of the new base.

The dependency hold is released. Structural model facts are separated from
contract-specific interpretations, with existing signatures and proof bodies
as the baseline. Nullable projection uses model types rather than the
application row alias. Package/frontend implementation remains incomplete.

The first source unit moves eight structural declarations to `ModelFacts`
and NULL projection to `ModelProjection`. Model preservation/extension helpers
import the structural facts; conformance laws drop their application import.
Logical observations stay application-owned. Proof bodies and statement
signatures are retained; structural types replace the application row alias.
Both actual isolated compiler checks pass in 11.59 seconds with a 120-second
command limit: a neutral consumer imports the facts and an application import
fails despite adjacent real source/artifacts. The hardened native application
build passes all 66 jobs under a 900-second limit, producing
`/nix/store/qh7qnknc536ndan68lrw4a53ipg1l8xz-sqlite-verifier-lean-runtime-1`.
Original XML and log are retained under `build/t10-structural-ownership-darwin/`.
The resource guard passes. Review `20261007T145948Z-e4a725f6` has no must findings.
Named import roots and project prefixes fix its policy-literal suggestion.
Both actual compiler checks pass in 7.65 seconds with a 120-second guard.
Independent correction review `20261007T150213Z-dbe963ae` reports no findings.

## Standalone package checkpoint

The standalone `packages/belay-sqlite` Lake package now supplies `Belay.Sqlite`
and the separate `Belay.Sqlite.Codec` library. Its thirteen core modules use
only model, Init and Std imports. Core module globs exclude the codec. The Nix
`modelPackage` selects only package source/configuration; missing required
configuration fails explicitly. Generated trees are excluded. Application
migration is still pending, so the existing application model remains in use;
its old paths will be deleted when callers move to the package.

The hardened Nix build compiles all 18 jobs with no application inputs. All
46 real source-identity checks pass in 24.95 seconds, including addition,
editing, rename, deletion, missing configuration, generated trees and
application-only changes. The final three package checks pass in 2.84 seconds:
core import closure, an unrelated installed-artifact consumer with codec
roundtrip/version/byte refusals, and a forbidden application import despite an
adjacent source checkout. Results are in
`build/t10-standalone-model-darwin/package.xml`. The tested artifact is
`/nix/store/2w1wn11c4gq07b4a1f422qfycphx18bj-belay-sqlite-model-0.1.0`.
The real nine-suite command ownership check passes in 1.07 seconds, with a
90-second outer limit. Authored Markdown file links resolve. Application
integration, the frontend, trust roots, offline installation and both native
final suites remain incomplete. This checkpoint awaits independent review.


## Package review corrections

Independent review `20261007T151915Z-46364462` has no mandatory findings and
six suggestions. Model laws now describe SQLite behavior, restate the rollback
assumption and result, and give proof sketches. The model record describes
schemas and statements. An unsupported codec version reports the received
version, the supported version and how to regenerate the inputs. The consumer
checks that diagnostic. Checked Verso documentation compiles, and all three
package tests pass in 16.27 seconds with a 120-second outer limit. The original
five documentation and diagnostic suggestions are recorded as fixed.

The source duplication suggestion is deferred to the next application
integration unit. That unit must update all callers and delete the original
model, laws and codec paths. No compatibility path is part of final T10
acceptance. Correction `0d37929f` passes independent review with no findings
(`20261007T152055Z-0d37929f`).


## Independent Python frontend checkpoint

The ten frontend modules move to `belay/sqlite/`, with independent SQL refusal
and admission modules. The parent namespace has no initializer and contains
only `sqlite/`. Normalized model types no longer import parser I/O or emit
Lean. `ExecutionProfile.wire_tag` supplies structural tags directly.
Application constructor and Generated input emission moves to
`migration_check/lean_inputs.py`. All old frontend implementation paths are
deleted, and current callers, experiments and local document links are updated.
Conformance calls the same admission function before execution and imports
no verification application module. Inert string quotation is shared transport.

The conformance frontend list uses full module names, and its import checker
resolves nested relative imports. A regression fixture follows a forbidden
application edge. Nix includes the new frontend in the runtime and affected
suites. CI selects packaging checks for frontend and model package changes.
The two new real-parser boundary checks belong to `harness`.

All 138 focused frontend, parser and generated-input parity checks pass in
26.37 seconds under a 180-second outer limit. All 373 source-owned checks
and 37 subtests pass in 44.94 seconds under the existing 600-second limit.
All 102 selected Nix identity, suite ownership, frontend closure and routing
checks and 37 subtests pass in 105.41 seconds under a 180-second limit.
Original XML files remain in `build/t10-standalone-model-darwin/`.
The final hardened runtime is
`/nix/store/jfbgdmz32id477ygz83550xfxrcp43nv-sqlite-verifier-runtime-1`.
The complete hardened harness passes all 122 checks in 2.520 seconds with
no failures, errors or skips. Its actual output is
`/nix/store/absh3bw7b34bf86s04dmrj69vxanp5cz-sqlite-verifier-test-harness-1`.
The final runtime and harness logs are retained beside the XML. Frozen corpus
and historical receipt bytes remain unchanged. Authored Markdown links resolve.

Model caller migration, deletion of the original Lean paths, runtime trust,
full native suites and installed archives remain required. This frontend unit
awaits independent review. T10 is not DONE.

The complete public CLI suite passes all 14 checks in
35.791 seconds under the same hardened sandbox and existing
suite limits. The launcher preserves positive, refutation and refusal outcomes
on the moved frontend. Its XML and build log remain retained; actual output
is `/nix/store/z065a6d9i9klrkmrz6n1gnxr6l1x48c5-sqlite-verifier-test-cli-1`.
