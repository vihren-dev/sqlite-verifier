# Status: T10 model package and SQL frontend

Created 2026-10-07. Status: IN PROGRESS.
Audience: team and reviewers.
Task: [task](20261007-model-package-and-frontend.task.md).
Specification: [accepted ADR 0006](../docs/adr-0006-model-boundary-and-execution-levels.md).
Source: [issue #31](https://github.com/vihren-dev/sqlite-verifier/issues/31).

## Current checkpoint

The standalone `Belay.Sqlite` model and `belay.sqlite` frontend are integrated
with the application. Replaced paths are deleted. Both compiled library
roots use the same resolution order for compilation, export and checking.
The original native macOS and Linux checks pass at their recorded sources,
including fresh installed archives. The Linux source run retains two optional
reviewer-tool skips. The owner's new review requests add a macOS casing fix,
passing targeted checks and a historical-plan link exemption. Full acceptance
at the final integrated head remains required. The owner will review that head
after PRs #57, #53, #50 and #59 are delivered and integrated. T07 stays paused.
Authorized cleanup is complete, and the resource guard passes before this work.

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
- [Lake configuration](../lakefile.toml), [model](../packages/belay-sqlite/Belay/Sqlite/Model.lean),
  [library](../SqliteVerifier/Library.lean),
  [nullable projection](../SqliteVerifier/NullableProjection.lean),
  [codec](../packages/belay-sqlite/Belay/Sqlite/Codec.lean) and
  [conformance laws](../packages/belay-sqlite/Belay/Sqlite/Laws.lean) show current ownership
  edges. Both schema lookups are structural dependencies of `Conforms`.
- [Frontend types and emission](../belay/sqlite/sql_model.py),
  [parser](../belay/sqlite/sql_tree.py),
  [translation](../belay/sqlite/translate.py),
  [records](../belay/sqlite/structural.py) and
  [inputs](../migration_check/inputs.py) show the shared-record boundary.
  Frontend types and records now have no application dependency. Application
  Lean emission lives in `migration_check/lean_inputs.py`. Shared refusal
  classes live in the frontend.
- [Source selection](../build-support/sources.nix),
  [Nix builds](../build-support/default.nix),
  [runtime assembly](../build-support/runtime.nix),
  [test targets](../build-support/tests.nix),
  [source identity checks](../tests/test_source_identity.py),
  [runtime fixtures](../tests/runtime_fixtures.py) and
  [CI scope](../tests/ci_scope.py) select the separate package and frontend.
- [Runtime discovery](../migration_check/runtime.py),
  [source resolution](../migration_check/source_closure.py),
  [preparation](../migration_check/prepare.py),
  [stage identity](../migration_check/stage_store.py),
  [kernel gate](../ProofChecker.lean) and
  [bundle gate](../BundleChecker.lean) use the same ordered pair of installed
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


## Frontend caller review correction

Independent frontend review `20261007T153011Z-a4ef6c5b` has no mandatory
findings and one suggestion. The latency diagnostic now catches both the
application rejection and frontend SQL refusal. Its parser recorder also
hooks `inputs.parse`, the current orchestration entrypoint, instead of the
removed `cli.parse` attribute. Both real refusal trials return their status
without compiling Lean or producing a traceback. The two new checks belong
to `bundle`; its Nix source includes the diagnostic and its case definitions.

All ten correction and frontend closure checks pass in 1.03 seconds. Four
actual command ownership and host exclusion checks pass in 1.77 seconds.
The real frontend suite invalidation check passes in 2.21 seconds after its
source fixture includes the new diagnostic inputs. Commands have 60- or
90-second outer limits; trial subprocesses have a 10-second limit. The
finding is recorded as fixed. This correction awaits independent review.


Correction review `20261007T153345Z-d356a7b1` has no mandatory findings and
one usage-text suggestion. The diagnostic now states that application and SQL
frontend refusals are recorded as statuses so remaining trials can run. This
text correction does not change execution. Its review remains required.


## Complete frontend bundle acceptance

Usage-text correction `e932980a` passes independent review with no findings
(`20261007T153603Z-e932980a`). The complete hardened bundle suite now passes
all 44 checks in 224.192 seconds, including both newly owned
latency diagnostic refusals. The suite retains its 1,200-second limit and
300-second per-test limit. The outer build command has a 1,500-second limit.
No failures, errors or skips occur. Original XML is in
`build/t10-frontend-bundle/junit.xml`, and the original build log is in
`build/t10-standalone-model-darwin/frontend-bundle.log`. The actual output is
`/nix/store/qb7hh56dmsanp1zrzl8g1h582xzh3gvs-sqlite-verifier-test-bundle-1`.

The source move and its caller corrections are committed and reviewed.
Model caller migration, removal of duplicate Lean paths, installed trusted
roots and both native final archives remain incomplete. T10 is IN PROGRESS.


## Application model integration checkpoint

The root Lake package requires `belaySqlite` at `packages/belay-sqlite`.
All old model, law and codec implementation paths are deleted. Current
application, example, conformance and test callers use `Belay.Sqlite`.
The production application root imports contract and interpretation helpers;
engineering examples have a separate Lake library dependency.

Nix builds the model independently, supplies that artifact to the application
at its declared package path and installs both compiled roots. Runtime discovery,
source staging, dependency resolution, export and cache identities use the
ordered sysroot, application and model roots. Both gates refuse missing or
colliding installed modules. Lean's explicit artifact-map API resolves the
first actual module file in that order, including caller-owned modules under
an installed namespace. Such declarations still require kernel replay.

All 373 source checks and 37 subtests pass in 46.23 seconds. All 93 actual Nix
source, derivation-dependency and suite identity checks pass in 106.61 seconds.
The full hardened model suite passes all 51 tests in 51.161 seconds; harness
passes all 122 in 2.221 seconds. All 41 kernel, generated-input and root checks
pass in 67.74 seconds. Separate namespace/refusal checks pass five tests in
12.85 seconds. Logs and original XML remain in `build/t10-model-integration-darwin`.
The complete bundle and CLI suites are checked before this unit's commit.

Seven approved-example source pins change for the explicit namespace move.
Their pin sets and raw SQL pins are unchanged. Final owner review covers those
source pins, the codec replacement and the changed gate/import boundary.
The review checklist follows the moved paths and retains its existing rules.
Frozen corpora, historical reports and the retained regression proof remain
byte-identical. The regression test reacquires its exact frozen case and
kernel-checks current emission instead of rewriting historical evidence.

Both native final suite sets and fresh installed archives remain incomplete.
Two new installed checks cover a neutral model/codec/application consumer and
an independent `belay.sqlite` import from the poisoned unrelated directory.
T10 remains IN PROGRESS. Independent review follows the checked source commit;
final owner review follows complete native acceptance.


The final hardened native model, frozen and harness suites pass 51, 145 and
122 tests in 55.717, 244.315 and 2.319 seconds, respectively. Bundle and CLI
pass 48 and 15 tests in 259.717 and 43.388 seconds. No failures, errors or
skips occur. The reporter now binds frontend hashes from `belay/sqlite`.
The initial frozen failure and initial old-root fixture failures remain in
their original logs; they are not relabeled. The final receipt and original
XML copies are in `build/t10-model-integration-darwin/checked-integration.json`.

All changed source files are below 200 lines. Authored Markdown links resolve.
No frozen corpus, historical report or retained regression artifact changes.
This complete source integration is ready for its independent commit review.
The remaining ordinary suites, both native final archives and final owner
review are still required; no release or delivery claim is made.


## Integration review and text correction

Independent review `20261007T164606Z-e38bc101` reports seven mandatory R8
owner-review flags and three text suggestions. It reports no code defect.
The seven flags cover root ordering and collision refusal, exact import
artifacts, source and bundle gates, the model types used by the contract,
export omissions and bundle invocation. They are recorded as deferred to the
explicit final owner gate after both native archive checks. The owner already
authorized tasks that need this final review; no design decision is pending.

The three suggestions are fixed. Gate comments describe the sysroot,
application library and model library. Compiler/cache docstrings use plain
sentences. The relative-root test override is named `application_library`,
because it replaces only that root. All 19 kernel tests pass in 35.11 seconds
with a 120-second outer limit. This text and fixture correction changes no
production execution or verification formula. It awaits independent review.


Correction review `20261007T164902Z-380c9de2` reports no code finding and two
R8 flags on comments only. Those findings are rejected as adding no new
trust-relevant change: import behavior, root selection and the verification
formula are unchanged by this correction. The original seven mandatory
owner flags remain pending. Final owner review includes the corrected
comments. No owner gate is waived or marked complete.


The completed macOS ordinary Nix evaluation selects 313 passing checks across
Atuin (12), bundle (48), CLI (15), harness (122), kernel (28), sample (12) and
upstream (76). The full model and frozen suites add 51 and 145 passing checks.
All nine suites have zero failures, errors or skips. Original JUnit timestamps
and immutable output paths are retained; cached outputs are not reported as
new executions. The final runtime rebuild passes. Fresh archive and installed
acceptance are still running and are not counted as passing.


The final macOS runtime `x52xw4fpnfmw7wdc7gc5pyi7gr813j1k` produces a fresh
content-verified archive. All 26 installed package and Atuin checks pass in
124.695 seconds, without failures or skips. Both new package checks execute
against installed files. [The native record](../reports/20261007-model-package-darwin/README.md)
retains the original bytes and binds the component inputs and archive. The
final comment correction changes suite input identities, so all affected Nix
suites are being rerun. Linux acceptance and final owner review remain pending.


Native installed evidence commit `1dd2df24` passes independent review
`20261007T170054Z-1dd2df24` with no findings. Retained raw-file SHA-256
values and byte counts also match after local verification. A draft PR will
run complete Linux package checks while final macOS Nix suites finish.
This publication does not request final owner approval or mark T10 done.


Draft [PR56](https://github.com/vihren-dev/sqlite-verifier/pull/56) is published
at `71d561ae`. Linux package CI run `37655729129` is queued. The PR retains
all final owner gates and states that current acceptance is incomplete. The
final macOS bundle suite runs first under the existing scheduling rule.


All final macOS checks pass on the reviewed input identities: 509 tests
across nine Nix suites; 373 source tests and 37 subtests; 102 Nix
infrastructure checks; and 26 fresh installed package and Atuin checks.
Original final XML, logs, node identities and output paths are retained in
the native report. Linux package CI is still running. Local free space is
below the 10 GiB threshold after these successful checks. No further
expensive local run will start without resolving that resource guard.


Final macOS evidence `bab5fe2c` passes independent review
`20261007T171937Z-bab5fe2c` with no findings. The Linux CI reports now
verify 509 passing Nix suite checks, 102 Nix infrastructure checks and
26 fresh installed checks. Its source XML records 371 passing tests,
37 subtests and two optional reviewer-tool skips. Original Linux ZIP, XML
and phase bytes are retained in [the Linux record](../reports/20261007-model-package-linux/README.md).
The job is still saving its cache; a final conclusion is pending. The
owner has been asked to approve one completed local test-temp directory
for targeted cleanup. No files are deleted while that answer is pending.


Linux CI `37655729129` is terminal successful, including cache retention
and artifact uploads. All recorded phase exit codes are zero. The Linux
evidence retains its original 18 artifact members and matching ZIP digest.
Both native platforms now pass the required full suites, infrastructure
checks and fresh installed archives. Final evidence review, publication and
owner approval remain required. No task completion or baseline approval is
claimed.


Linux evidence `bb029cdd` passes independent review
`20261007T172554Z-bb029cdd` with no findings. The exact ZIP inventory has
18 members; all 18 original XML and JSON members are retained separately,
and their hashes and sizes match. Final macOS and Linux acceptance are
complete. The implementation is ready for final owner review after this
evidence publication and the final head checks. T10 remains IN PROGRESS
until owner approval and normal delivery.

## Decisions waiting for the owner

- Review the codec, exact gate artifact selection, trusted root ordering,
  verification target, export omissions and checker invocation. Seven
  mandatory flags remain recorded in `20261007T164606Z-e38bc101`.
- Review the seven example source-pin changes for the model namespace.
  Baseline enforcement and raw SQL pins are unchanged.


PR56 is ready for final owner review at published head `0e8c57a2`. Its
final-head Linux CI `37659387986`, job `112922702589`, succeeds. The macOS
PR job skips checks; complete native macOS evidence is retained separately.
The protected baseline check requires explicit owner review of the changed
pins. The published branch is frozen during review except for requested
fixes. This local status checkpoint does not move that branch. Approval,
normal merge and task closeout remain pending.


The owner approved the pending targeted cleanup on 2026-10-07. Only
`/private/tmp/nix-shell.xSzEcW/pytest-of-tzankomatev/pytest-6` was removed.
The retained final Nix XML and compressed log were verified before removal.
The cleanup reclaimed about 1.8 GiB; the measured free space afterward is
15.824 GiB. The local receipt is
`build/t10-model-integration-darwin/cleanup-receipt.json`. The disk threshold
is satisfied. Main now includes delivered T13, so PR56 requires integration
before merge. Its current owner-review head remains unchanged.
# Owner review changes, 2026-10-08

The owner requests a differently cased caller-module test on macOS and an
exemption for historical plan links. Added actual caller proof tests under
`SqliteVerifier.Candidate`, `Belay.Sqlite.Candidate` and
`belay.Sqlite.Candidate`. The lowercase package failed on the prior runtime:
Lean selected the installed package directory and missed the caller module.
The import-path helper now groups directory names according to the destination
filesystem's case behavior and preserves first-root precedence for collisions.

A freshly built immutable macOS runtime passes all 18 selected documentation,
import-path, real compiler, caller replay, current example and exporter boundary
checks. Original failed and successful logs, XML, source hashes and runtime
identity are in `reports/20261008-model-package-owner-review-changes/`.
Restored 10 historical plan records from accepted base `eb061e76`; maintained
documentation still rejects broken local links. Historical records will be
checked again against final integrated main. No earlier acceptance receipt is
rebound to this change.

Decisions waiting for the owner:

- Review PR #56 after PRs #57, #53, #50 and #59 are integrated and checks pass.
  Protected source pins and trust changes still require that final review.
