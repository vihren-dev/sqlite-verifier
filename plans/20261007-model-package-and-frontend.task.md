# T10: Separate the SQLite model package and SQL frontend

Created 2026-10-07. Status: IN PROGRESS.
Audience: implementers and reviewers.
Status file: [status](20261007-model-package-and-frontend.status.md).
Specification: [accepted ADR 0006](../docs/adr-0006-model-boundary-and-execution-levels.md).
Source: [issue #31](https://github.com/vihren-dev/sqlite-verifier/issues/31).

## Observable behavior when done

The SQLite model is reusable without the migration contract, CLI, demonstrations
or example proofs. Its separate Lake package is `packages/belay-sqlite/`, with
its own `lakefile.toml` and manifest. The root Lake package requires `belaySqlite`
through that relative path. The core library and namespace are `Belay.Sqlite`.
Its transitive imports use only model modules, `Init` and `Std`. A separate
same-package library, `Belay.Sqlite.Codec`, may use `Lean` and the core. The core
does not import the codec. An independent model build has no application sources
or application dependency, even when a checkout exists beside the build.

Model types, existing execution, profiles, validity and support predicates,
preservation facts and conformance laws belong to the model. Theorem ownership
follows each statement and its dependencies. Mixed files are split so that a
model fact needs no contract import. `Schema.lookup`, `Schema.lookupProperties`
and their structural laws remain model-owned because `Conforms` uses them.
Requirement-oriented helpers, interpretations, `LogicalContract` and
`VerificationConditions` remain application-owned. Structural projection and
NULL-extension facts use model types instead of the application `LogicalRows`
alias. Demonstrations and example proofs are test or example dependencies.
For example, `Conforms.set`, `Database.set_comm` and `TableExtends.project`
are model facts; `projectedInterpretation_sound` and
`unreachableFailures_sound` stay with the contract.

The Python frontend is imported as `belay.sqlite`. At the initial split,
`belay/` is a namespace directory without `__init__.py` and contains exactly
the `sqlite/` subdirectory. All frontend modules live below `belay/sqlite/`.
This contract leaves the leaf initializer choice open. It does not restrict
namespace portions supplied by other distributions.

The frontend owns pinned parser invocation, normalized structural types,
supported-subset translation and structural record encoding. It accepts explicit
parser and profile inputs. It imports no CLI, runtime discovery, contract,
approval, baseline or Lean compiler code. Source coordinates and refusal
classifications remain available to callers. Application-specific Lean emission
and reserved `Generated` declarations stay in the application. Conformance uses
the same frontend and model codec without depending on the verification contract.

Nix selects the complete model package and its configuration as a separate
component and builds it with the pinned toolchain. The application uses that
built package at the declared relative path, without network resolution or a
caller checkout. Application-only changes leave the model derivation unchanged.
Model source or configuration changes invalidate the affected model, application
and test artifacts. Missing required package inputs fail explicitly.

The runtime installs application modules at `.lake/build/lib/lean` and model
modules at `packages/belay-sqlite/.lake/build/lib/lean`. It retains the package
configuration and relative dependency layout in its installed source snapshot.
Existing checker and exporter executable paths, parser paths, public launcher,
CLI commands and distribution names retain their names. Production library
imports exclude demonstrations and test runners; conformance adds its runner
separately.

Runtime discovery supplies the ordered trusted roots: pinned Lean sysroot,
application library and model library. Compilation, dependency discovery, both
kernel gates and export use the same roots. Approved and candidate directories
are exposed only to their required stages. Exact installed module origins and
the transitive trusted import closure determine exporter omissions. A submitted
declaration under a model-like namespace remains submitted evidence when its
origin lies outside that closure. Missing or colliding installed modules fail.
Ambient `LEAN_PATH`, Python paths and caller Lake manifests grant no trust.
Runtime and stage identities bind both package artifacts and the toolchain;
an application-only cache entry cannot satisfy the new layout.

The offline runtime archive supplies both compiled roots and the frontend.
From an unrelated directory, it can compile a neutral model consumer, prepare
proofs and check bundles without the source checkout, downloads or a separate
model installation. The gates still compare protected declarations, replay
submitted declarations in the kernel, audit the existing axiom policy and
reconstruct the verification target independently. The codec remains transport.

Existing success, failure and pending outcomes, stopping positions, visible and
persisted state, admitted profiles, refusal meanings and example statuses retain
their meaning. The structural format retains its version, typed values, tags,
field names and index-order rules. Frozen v1–v5 bytes, historical reports and
their replay readers remain unchanged. Current proof artifacts and identities
reflect the intentional namespace move; historical receipts are retained.

All callers move to the new owners and imports. Replaced model and frontend
implementation paths are deleted, with no aliases or fallback imports. Existing
application names remain valid outside `Belay.Sqlite`. Public declarations and
their checked Verso docstrings change together. Model text describes SQLite
state and behavior. Sources remain below 200 lines, with complete Python types.

## Acceptance suite

- Actual isolated Lake and Nix builds import core model declarations, execution,
  lookups, projection facts and conformance laws without the application. A
  deliberately introduced application import fails the isolated model build,
  including when an application checkout exists beside it. Core transitive
  import checks reject `Lean` and codec imports. The separate codec builds and
  decodes the existing structural records using `Lean`.
- Theorem-ownership checks and neutral consumers cover model facts currently
  reached through `Library`, `LiteralPreservation`, `SchemaExtension`,
  `SchemaPreservation` and `NullableProjection`. Contract-specific wrappers
  remain available to application callers. Model comparison and laws import
  no contract, demonstration or example proof.
- Source and installed Python checks import `belay.sqlite` independently of the
  application. They validate the exact parent namespace layout and reject
  application dependencies. Real pinned parser checks retain source spans,
  admitted output and unsupported-input diagnostics. Shared record tests compare
  frontend output, application Lean emission and codec decoding, including
  typed values, profiles and both index-order policies.
- Real Nix source and derivation identity tests cover package additions, edits,
  renames, deletion and missing required files; application-only edits; and
  excluded generated trees. Relevant cached test targets depend on the moved
  package and frontend inputs. CI selects package checks for these changes.
- Actual compiler, resolver, exporter and gate checks resolve both installed
  roots in the declared order. They cover direct and transitive model imports,
  unrelated namespaces, a candidate under `Belay.Sqlite`, attempted replacement
  of a protected module, conflicting installed modules and missing model
  artifacts. Old runtime cache identities are refused or rebuilt. Every existing
  kernel attack and generated-input parity check remains effective, including
  changed starting schema, script, profile and forged generated declarations.
- A caller under differently cased `belay.Sqlite` passes actual preparation,
  export and kernel replay on macOS. Filesystem-aware package merging retains
  first-root precedence for colliding artifacts. Historical plan records keep
  their original source paths and are exempt from current-document link checks;
  broken links in maintained documentation still fail.
  Deterministic original-root checks cover both root orders and matching or
  different package spellings. Mixed filesystem case modes retain original
  package search paths instead of combining their casing rules.
- On native `aarch64-darwin` and `x86_64-linux`, build a fresh runtime archive and
  run actual installed acceptance with `--runtime-variant installed` and
  `--runtime-archive`, without substituting a development runtime root. Poison
  ambient Python and Lean paths and use an unrelated working directory. Import
  core, codec and application modules from installed roots and compile a neutral
  consumer. Existing source verification, installed preparation and bundle
  checking retain positive, checked-refutation, wrong-SQL and Atuin results.
- Both platforms pass current `just test`, the affected Nix infrastructure
  checks, the full model and conformance suites, kernel and bundle suites, and
  native installed package and Atuin acceptance. Replay frozen v1–v5 and run
  authored, generated and mutation cases. Retain selected node identities,
  counts, verdicts, source/runtime/archive identities, commands, logs and JUnit
  bytes. Prior receipts, synthetic checks or unsupported-only reports do not
  replace actual acceptance on the new implementation.

Every test and subprocess has an explicit timeout. Short dependency and identity
checks use bounded fixtures; full and installed suites retain the configured
bounds of the delivered base. A timeout change requires its own evidence and
review. Missing tools, credentials, platforms or a specification contradiction
stop affected work under the workspace rules. No performance claim or timing
campaign is part of this task.

Independent review follows [the checklist](../docs/review-checklist.md) after
each checked implementation commit. R8 final owner review is required for the
codec, runtime trust, exporter and gate changes after implementation and all
required evidence are complete. T10 and issue #31 are complete only after those
checks, review and repository delivery.

## Relevant source and tricky constraints

| Boundary | Current source and constraint |
| --- | --- |
| Lake and ownership | [lakefile](../lakefile.toml), [public root](../SqliteVerifier.lean), [model](../packages/belay-sqlite/Belay/Sqlite/Model.lean), [library](../SqliteVerifier/Library.lean), [nullable projection](../SqliteVerifier/NullableProjection.lean) and [conformance laws](../packages/belay-sqlite/Belay/Sqlite/Laws.lean) mix structural and application imports. Classify declarations individually. |
| Codec and generated inputs | [StructuralCodec](../packages/belay-sqlite/Belay/Sqlite/Codec.lean), [BundleChecker](../BundleChecker.lean), [sql_model](../belay/sqlite/sql_model.py), [sql_values](../belay/sqlite/sql_values.py), [profiles](../belay/sqlite/profiles.py), [structural records](../belay/sqlite/structural.py) and [inputs](../migration_check/inputs.py) share data with Lean emission. Model transport and application declarations have different owners. |
| Frontend errors | [parser trees](../belay/sqlite/sql_tree.py), [translation](../belay/sqlite/translate.py), [schema translation](../belay/sqlite/schema_translate.py), [admission](../belay/sqlite/sql_admission.py) and [diagnostics](../migration_check/diagnostics.py) currently share application status types. Preserve coordinates and status meanings without importing application policy into the frontend. |
| Build and install | [source sets](../build-support/sources.nix), [builds](../build-support/default.nix), [runtime assembly](../build-support/runtime.nix), [test targets](../build-support/tests.nix), [archive builder](../packaging/build_runtime.py), [runtime fixtures](../tests/runtime_fixtures.py), [identity tests](../tests/test_source_identity.py) and [CI scope](../tests/ci_scope.py) assume one package root. Include configuration, compiled dependencies and all moved test inputs. |
| Trust and reuse | [runtime](../migration_check/runtime.py), [source closure](../migration_check/source_closure.py), [compile](../migration_check/compile.py), [contract](../migration_check/contract.py), [prepare](../migration_check/prepare.py), [stage store](../migration_check/stage_store.py), [GateCore](../GateCore.lean) and [ProofChecker](../ProofChecker.lean) assume one application library. Preserve stage isolation and protected-declaration checks while adding the model root. |
| Export and execution base | Approved [PR47](https://github.com/vihren-dev/sqlite-verifier/pull/47) supplies exact-origin omission and a shared view for Lean's split package-directory resolution. Approved [PR48](https://github.com/vihren-dev/sqlite-verifier/pull/48) supplies the single SQL executor and corrected proof guards. Use their delivered source rather than resurrecting the deleted executor or exporter patch. |
| Other callers | [model runner](../conformance/model_check.py), [native replay](../conformance/native_replay.py), [mutation harness](../conformance/mutation_check.py), [coverage instrumentation](../conformance/instrument_model.py), examples, source fixtures and tests embed model names or paths. A namespace search alone does not update source extraction boundaries or Nix input lists. |

## Scope and dependency delivery

The accepted ADR in PR44 and approved exporter and executor changes in PR47
and PR48 are delivered. Implementation starts from reviewed main `eb061e76`.
Held T07, T15 and T18b work is not part of that base. Their historical source
and receipts remain separate from this task's acceptance.

This task implements the accepted package boundary. It does not implement
T07 table shapes, T08 validity changes, T11 execution categories or new SQL
features. The existing single-executor behavior is the migration baseline.
Issues #23, #27 and #28 remain separate; broad application vocabulary,
repository, CLI and distribution renames remain deferred. This task creates
no new performance tolerance or standalone model release requirement.
