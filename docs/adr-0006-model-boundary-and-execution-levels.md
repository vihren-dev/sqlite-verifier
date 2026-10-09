# ADR 0006: SQLite model boundary and execution levels

Date: 2026-10-06. Status: ACCEPTED on 2026-10-07.
Audience: designers and reviewers.
Sources: [#23](https://github.com/vihren-dev/sqlite-verifier/issues/23),
[#31](https://github.com/vihren-dev/sqlite-verifier/issues/31).
Task: [architecture decision](../plans/20261006-model-architecture.task.md).

## Context

The [root Lake package](../lakefile.toml) builds the model and verification
application together. [Its public module](../SqliteVerifier.lean) imports both,
including demonstrations. The model's basic dependency direction is correct,
but model lemmas in `Library`, `LiteralPreservation`, `SchemaExtension` and
`SchemaPreservation` pull in the contract. Model validation also reaches it
through `NullableProjection`. SQL translation and application Lean generation
share normalized types in [sql_model.py](../belay/sqlite/sql_model.py).

[Execution](../packages/belay-sqlite/Belay/Sqlite/Execution.lean) and
[SqlExecution](../packages/belay-sqlite/Belay/Sqlite/SqlExecution.lean) dispatch through `advance`,
`literalStep` and `step`. Their catch-all cases let an added constructor escape
an explicit domain or effect decision. Positions travel through every level,
and data atomicity and constraints are tied to literal writes.

This ADR fixes the architecture for the package split and later restructuring.
It adds no supported SQL syntax and makes no new native-conformance claim.
The CLI commands, distribution names and existing application vocabulary remain
unchanged. No compatibility aliases preserve modules replaced by either change.

## Package and ownership decision

The model is a separate Lake package at `packages/belay-sqlite/`, with its own
`lakefile.toml` and manifest. The root package requires `belaySqlite` through
the relative path `packages/belay-sqlite`. Its model namespace and core library
are `Belay.Sqlite`. The root application imports that package; the model has
no dependency on the root package. Independent distribution can be added later.

The core entry point imports only model declarations, execution and model
lemmas. Its transitive dependencies may use `Init`, but not `Std`, `Lean` or
application modules. `Std` is excluded because the model does not use it and
every importer, including the kernel gates, pays its import cost. A separate `Belay.Sqlite.Codec` library in the same
package may import `Lean` and the core. The core never imports the codec.
The codec contains the model-value/statement/profile transport currently in
[packages/belay-sqlite/Belay/Sqlite/Codec.lean](../packages/belay-sqlite/Belay/Sqlite/Codec.lean). Construction of the application's
`Generated` declarations stays with the application, using those codecs.

| Owner | Contents |
| --- | --- |
| `Belay.Sqlite` core | Values, columns, table/schema/database types, SQLite validity and model support predicates, profiles/settings, execution, model preservation lemmas and conformance laws. |
| `Belay.Sqlite.Codec` | Structural model decoding/encoding and closed-term transport; no verification target or application declarations. |
| Root application | Contract, interpretations, contract-specific projection and failure helpers, generated declarations, gates, approval and baseline checks. Its imports remain outside `Belay.Sqlite`. |
| Test code | Demonstrations, example proofs and runner/observation transport; the model laws and model comparison import no contract. |

Move a theorem by its statement and dependencies. A result about model types
alone belongs to the model, even when the application uses it. A result about
`LogicalContract`, `Interpretation` or `VerificationConditions` belongs to the
application. Split mixed files; do not move them wholesale across the boundary.
Model docstrings describe SQLite state and behavior, without approval roles.

For example, `Library`'s `Conforms.set`, `Database.set_comm` and
`TableExtends.project` are model facts; `projectedInterpretation_sound` and
`unreachableFailures_sound` require the contract. `LogicalRows` is currently an
application alias for the structural type already returned by `Table.project`.
Model lemmas use that structural projection type without importing its
application alias. The nullable-column projection theorem and its structural
NULL-extension operation follow the same rule; interpretation wrappers stay
outside. This removes the contract dependency from the conformance laws.

`Conforms` currently uses both `Schema.lookup` and `Schema.lookupProperties`.
These are structural model operations, so the split retains model-owned lookup
primitives and the lemmas that use them. A requirement-oriented convenience
helper belongs to the application. Classification follows actual callers;
moving a lookup needed by `Conforms` would create a dependency cycle. The later
table-shape change in [#15](https://github.com/vihren-dev/sqlite-verifier/issues/15)
can replace column/property comparisons and remove obsolete descriptions.
It is not a prerequisite of the package split.

The separate Python frontend uses the import package `belay.sqlite`. Its parent
`belay/` directory is a namespace package: it has no `__init__.py`. At the initial
package split, `belay/` contains exactly one entry, the `sqlite/` subdirectory.
All frontend modules live under `belay/sqlite/`.

The frontend owns pinned
parser invocation, normalized structural types, supported-subset translation
and structural record encoding. It takes explicit parser/profile inputs and
imports no CLI, runtime discovery, contracts, baseline code or Lean compiler.
Parsing produces model records; application code converts them into reserved
`Generated` names and declarations. Source spans remain available for diagnostics.
Conformance uses the same frontend and codec, independently of the application.

The transport remains the existing
[structural format](conformance-format-v1.md), including its validated typed
values, profiles and index-order rules. A category added to the internal Lean
types does not silently change a frozen wire tag. Adapters map those tags to
the categorized types exhaustively. A later wire change needs a new version;
frozen records and their replay readers remain evidence.

## Semantic levels

| Level | Reads and produces | Responsibility |
| --- | --- | --- |
| Values | Values to values/predicates | Affinity, coercion, comparison and NULL rules. |
| Expressions | One row and declared inputs to a value/error | Literal and column evaluation; shared operators when added. |
| Queries | Database to rows/error | Shared read semantics when query support is added. |
| Statements | Database to tentative database/error | Schema and data effects, with their admitted domains. |
| Connection | Statement and connection state to next state/error | Transaction control and publication of atomic statement effects. |
| Script | Statements and connection state to `Outcome` | Zero-based positions, first-error stopping and final transaction visibility. |

Each level uses only lower-level semantics. Data types and errors are shared
model declarations, not imports from the contract. Keep source modules below
200 lines by separating responsibilities. The initial expression surface needs
only existing literal and column behavior. The query boundary reserves the
place for future query semantics; this change does not implement or admit
`SELECT`, `DELETE`, `INSERT ... SELECT`, triggers, cascades or savepoints.

`Statement` has exactly three current categories: `schema SchemaStatement`,
`data DataStatement` and `transaction TransactionStatement`. Their constructors
cover today's CREATE TABLE, ADD COLUMN, INSERT, UPDATE, BEGIN, COMMIT and ROLLBACK.
Every category and top-level domain/effect match has explicit constructor cases;
no catch-all forwards to another executor or silently admits a new statement.

Each category has an `Admitted` predicate beside its effect. SQLite validity
rules and modeled-domain restrictions remain distinct, as required by
[#18](https://github.com/vihren-dev/sqlite-verifier/issues/18). A restriction
causes refusal before model comparison, rather than a predicted SQLite error.
Reached-state admission remains checked in execution order; an unreachable
suffix after a modeled error does not acquire a new support requirement.

Schema/data effects return a tentative database or an `ExecutionError`, without
positions. Transaction effects operate on `SqlState`. One shared data-constraint
check validates tentative data results. Connection execution publishes a
tentative result only after those checks succeed; an ABORT-style statement
failure retains the incoming statement state. New data statements use that
same path. Their effects do not implement separate rollback or constraint paths.

Only the script level attaches the statement position to a failure and stops
the sequence. It preserves `Outcome.success`, `Outcome.failure` and
`Outcome.pending`, including the distinction between persisted and visible
databases. BEGIN records the committed snapshot; COMMIT and ROLLBACK are
explicit SQL operations. An open transaction at EOF remains pending. Failure
inside it retains prior successful visible changes and the committed snapshot;
it does not imply connection closure or rollback of the whole script.

`ProfileExecutes` remains the relation used by `VerificationConditions`, with
the same arguments and meaning. The executor starts at position zero outside
a transaction. Profiles retain their fixed SQLite semantics and admission
assumptions. Equivalence theorems connect the refactored computation and relation
to the existing outcomes for the admitted domain; their plain-words statements
explain the assumptions. Contract formulas are not weakened to ease migration.

Adding a statement later requires its constructor, domain, effect, transport
mapping and native evidence in one scoped feature task. Missing cases fail the
Lean build. New expressions and queries use their common levels. A future
trigger/cascade feature must define its fuel and transaction semantics before
recursive execution is added; this ADR makes no termination or coverage claim
for those future features.

## Nix, runtime and trusted imports

The source selection in [sources.nix](../build-support/sources.nix) gets a model
component containing the complete model package and its configuration. It has
no application source. [default.nix](../build-support/default.nix) builds that
component by itself with the same pinned Lean toolchain as the application.
The application source set contains its own code/configuration and the explicit
path dependency. Nix supplies the already built model at that relative path;
Lake never fetches it from a network or resolves it from a developer checkout.
The model artifact identity includes its source/configuration and toolchain.

An isolated model build has only its source and declared standard dependencies.
A negative fixture that imports an application module must fail there even
when an application checkout exists beside it. Core import-closure checks also
reject `Lean` and codec dependencies. The codec's own build may use `Lean`.
Application edits leave the model derivation unchanged; model edits invalidate
its dependent application and model-test outputs. Component-identity tests
cover additions, edits, deletion and missing package inputs.

[Runtime assembly](../build-support/runtime.nix) installs application artifacts
at `.lake/build/lib/lean` and model artifacts at
`packages/belay-sqlite/.lake/build/lib/lean`. Keep the model package configuration
and relative dependency layout available in the installed source snapshot.
Checker/exporter executables remain under `.lake/build/bin`; parser paths and
the public launcher remain unchanged. Production omits test runners/examples
as library imports; conformance builds add their test-only executable separately.

Runtime discovery owns one explicit ordered set of trusted roots: pinned Lean
sysroot, application library, model library. Every source compiler, dependency
resolver, gate and exporter uses that set. Candidate/approved work directories
are added only in the stages that need them. No ambient `LEAN_PATH`, caller
Lake manifest or namespace prefix grants trusted status. Runtime/stage identities
bind both package artifacts and the toolchain, so an old application-only cache
cannot satisfy the new layout. Missing or colliding installed modules fail.

Trusted module resolution records exact module identity and installed package
origin, including the transitive closure. The replacement exporter in
[#29](https://github.com/vihren-dev/sqlite-verifier/issues/29) derives its omission
set from exactly the declarations supplied by the checker through that closure.
Moving a module to `Belay.Sqlite` never makes unrelated submitted declarations
trusted by name. Both package roots participate in protected-declaration
comparison and kernel replay; the axiom policy and independently reconstructed
verification target retain their meaning. The codec remains transport, not a
proof oracle. Trust-relevant implementation changes need final owner review.

The [offline archive](../packaging/build_runtime.py) exports the entire Nix
closure containing both package outputs. Installed acceptance runs from an
unrelated directory with poisoned ambient Python/Lean paths: import core model,
codec and application modules from installed roots; compile a neutral consumer;
and run verification/preparation/bundle checking with the existing positive,
checked-refutation and wrong-SQL results. The archive must provide those paths
without source checkout access, downloads or a model-specific installation step.

## Implementation acceptance and consequences

The package split precedes table shapes, validity changes and executor layers.
Existing proofs first move to the single SQL executor under
[#21](https://github.com/vihren-dev/sqlite-verifier/issues/21). The later execution
restructure preserves that baseline inside the model package. Each change updates
public Verso documentation with its declarations; product/vocabulary renames
remain separate work.

Required implementation evidence is: isolated positive/negative model builds;
import and theorem-ownership checks; independent Python frontend imports;
Nix source-identity and offline installed-path checks; generated-input parity;
equivalent existing outcomes and example statuses; kernel attack tests; and
conformance replay plus `just test` on both supported platforms. All checks have
timeouts. Frozen evidence and refusal classifications retain their meaning.
Passing this ADR's review is not evidence that those future checks already pass.

The separate package adds one dependency and explicit runtime roots, while
removing accidental application imports from reusable model consumers. It
requires build/runtime/exporter changes together with the namespace move.
The owner accepted this ADR on 2026-10-07 with the Python namespace layout above.
Package and execution implementation remains gated to its separate tasks and
unstarted by this ADR update.
