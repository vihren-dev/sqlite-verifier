**Lean SQLite Migration Verifier — Engineering Brief**

Revision 0.6 · 25 September 2026

Build a tool that verifies one migration SQL file against reusable human-approved requirements. The human approves the logical model, requirements, current interpretation, and assumptions. The agent supplies the migration, resulting interpretation, and proofs. Check them under the supplied execution profile; return `0` on success and nonzero with diagnostics otherwise. One migration may contain multiple SQL statements.

The implementation being checked is a `(schema, interpretation)` pair. Interpretations map concrete database states to the fixed logical model and declare their representation invariants; they may remain unchanged across a migration. Requirements stay independent of candidate migrations and can be reused in separate invocations. Generated obligations and proofs are migration-specific.

SQLite is the first backend. Preserve a path to PostgreSQL through backend-independent interfaces and reusable relational libraries, without requiring its implementation in the initial delivery.

**SQL-only product boundary.** Schema and migration SQL files are the universal
interface. The core does not integrate with ORMs or migration frameworks, read
their catalogs, or add their bookkeeping and transaction operations implicitly.
Execution profiles describe SQLite settings that affect semantics; application
data assumptions and migration-history facts belong in approved requirements and
interpretation invariants. Any database operation covered by the claim must be
explicit in the supplied SQL and checked using reusable SQL semantics.

Real-project examples need only reasonable schema and migration SQL, source-backed
requirements and interpretations, proofs, and a README linking to a pinned upstream
commit and relevant source/documentation fragments. Explain why the SQL represents
the selected migration and why the logical model matches application behavior.
Do not require importing or building the application, reproducing its framework,
or certifying a live runner. Explicitly document any runtime-value instantiation
and limits of the SQL example's equivalence claim. Framework integrations and
invocation certification are outside this stage's scope.

**Development and distribution.** The engineer must establish the following as part of project setup:

- **Repository:** create the local Jujutsu (`jj`) repository at `~/work/sqlite-verifier` and connect it to the public GitHub repository `vihren-dev/sqlite-verifier`. Create and configure both repositories; use `jj` for local version control.
- **Environment:** manage development dependencies with `flake.nix`, commit `flake.lock`, and integrate direnv through a checked-in `.envrc`. Pin the Lean toolchain and the selected SQLite release consistently with the supported execution profile. Document onboarding and a `nix develop` entry point for environments without direnv.
- **Commands:** provide a `justfile` for frequently used build, test, check, and packaging commands. Keep the recipes usable locally and in CI, using the same Nix-managed dependencies.
- **CI:** use GitHub Actions to run the test suite and required checks on pull requests and pushes to the main branch. Run the same commands locally and in CI, including proof checks, parser/conformance regressions, and coverage reporting. CI must build and retain user-installable artifacts for the declared supported platforms, including required runtime files, and smoke-test the packaged tool on a representative verification example.
- **Releases:** publish new versions through GitHub Releases. A version tag must trigger the checks and artifact build; publish the resulting CI-built artifacts with release notes and installation instructions after successful verification. Document the release procedure and supported platforms.
- **License:** release the code as open source under the MIT license and include the license text in a root `LICENSE` file. Retain required notices for incorporated third-party code.

**User interface.** Accept these inputs:

| Input | Contract |
| --- | --- |
| `Requirements.lean` | Approved logical model, validity predicates, preservation/allowed-change requirements, and assumptions; unchanged by the proposed migration. |
| `schema.sql` | Ordinary SQLite `.schema` output describing the current schema. |
| `Interpretation.lean` | Accepted current interpretation and representation invariant. |
| `migration.sql` | One proposed migration, containing one or more SQL statements. |
| `NextInterpretation.lean` | Proposed interpretation and representation invariant for the resulting schema; may reuse the current definitions. |
| `Proofs.lean` | Representation and migration proofs discharging the generated obligations. |
| `--profile` | Required execution profile; initially a single string containing the supported SQLite version. |

Illustrative invocation (`X.Y.Z` stands for the release pinned at development start):

```sh
migration-check verify \
  --profile 'X.Y.Z' \
  --schema schema.sql \
  --interpretation Interpretation.lean \
  --migration migration.sql \
  --next-interpretation NextInterpretation.lean \
  --requirements Requirements.lean \
  --proofs Proofs.lean
```

Support `--format json`. Generate the SQL representation, resulting schema, and proof targets internally. Check the supplied script from the current schema/interpretation to the proposed resulting interpretation. Multi-migration orchestration, history, composition across invocations, and reverse/round-trip checking are outside the current scope. Optional workflow and audit wrappers can be added externally later; no certificate output or management is required.

Offline verification quantifies over starting databases satisfying approved conditions; it needs no data dump. Its result concerns this proposed migration, not evidence of actual execution.

**Execution profile.** Pin one exact SQLite release at development start. Initially the profile is its version string: an exact match proceeds to normal verification; another version produces `UNSUPPORTED`, reports requested/supported versions, and exits nonzero. A missing or malformed profile is an input error. Consider additional SQLite versions only after completing the pinned-version implementation. Useful releases may cover progressively larger semantic subsets of that version.

Discover configuration dependencies during development. Fix and document supported values, adding profile fields only when needed; defer a comprehensive configuration format. Account for relevant build/runtime settings, functions, collations, extensions, and connection behavior before verifying dependent features. Model or reject SQL that changes these settings. Align native tests with the model's environment assumptions. Offline checking assumes the declared environment; a future execution command checks the actual environment.

**Business model and schema ownership.** Define application entities independently
of database rows and physical layout. Requirements primarily constrain these
entities and their allowed changes. The supplied schema.sql is the single authored
complete schema declaration; the tool generates its Lean representation and binds
the approved interpretation to it. An interpretation supplies table/column mappings,
decoders and representation invariants, and proves their compatibility with the
generated schema. Do not require users to maintain a duplicate Lean schema.
Schema-only generated definitions may be visible to approved models; candidate
migration definitions and resulting schemas must not shape approved requirements.
Application migration-history facts are representation invariants, not engine
settings or business entities by default. Decoding assumptions and abstractions
from application source must be explicit, with no silently omitted protected rows.

**Interpretation contract.** Fix logical state type `L`, validity predicate `I : L → Prop`, and reusable preservation/allowed-change predicate `Q : L → L → Prop`, relating the migration's before and after states. Define current and resulting representation invariants `V_before`, `V_after` and interpretations `α_before`, `α_after`. Each invariant must imply conformance to its schema, interpretation definedness, and logical validity. Cover all required entities/fields; do not silently discard malformed or unmatched protected records. Interpretations read the represented database and approved fixed context; proof-only copies of old data cannot substitute for data lost from resulting storage.

The human approves the current meaning; the agent may author its definitions and proofs. The proposed interpretation requires proof against the supplied current representation under the fixed contract. Establish starting validity from approved conditions or justified runtime checks. Where schema constraints do not enforce representation invariants, document the additional conditions and prove that this migration respects them.

**Verification contract.** Establish the following for admitted starting states and every modeled execution outcome:

- Approved starting conditions establish `V_before(D)` and `I(α_before(D))`.
- Every successful execution from `D` to `D'` establishes `V_after(D')` and `Q(α_before(D), α_after(D'))`, together with the approved resulting-schema and postcondition requirements.
- Additional intermediate conditions follow from established facts or approved checks. The agent cannot introduce an unproved precondition to narrow an obligation; a rejected runtime check must leave the promised safety properties intact.
- Failure outcomes satisfy the declared failure/rollback contract and identify the resulting schema and interpretation. Applicability and progress are explicit; missing execution cases must not permit vacuous verification.

Final-only postconditions are obligations on the result, not assumptions about the input. No transitivity or reflexivity requirement is imposed on `Q`.

Verify the script's statement order and transaction behavior under the profile. One file does not imply one atomic transaction. Internal statements may temporarily violate representation invariants where permitted; any required intermediate-state guarantees must be explicit. A successful-run theorem must not be reported as guaranteed applicability, failure safety, or crash safety.

Check the expected theorem for the actual supplied SQL, interpretations, invariants, requirements, dependencies, and profile. Successful project compilation is insufficient. Reject unfinished proofs, unauthorized axioms, and additional unproved assumptions. The calling project/CI supplies and protects the approved requirements, their dependencies, and the current interpretation. The agent proposes the resulting interpretation separately; deliberate requirement changes follow human review. Maintain an allowlist for foundational axioms and trusted proof mechanisms.

Document the trusted boundary: parsing, SQL-to-Lean translation, proof dependencies, and correspondence between the model and native SQLite. Native-engine conformance is supported by documentation and tests unless separately proved; verifying SQLite's C implementation is outside the initial scope.

Offline checking does not enforce live execution. A future execution command must establish assumptions and apply the exact checked migration while controlling interference. Application-query compatibility requires an explicit connection to the approved logical observations.

**Parser.** Pin the source revision, documentation snapshot, and test corpus for the selected SQLite release.

Target the complete SQL grammar of that pinned build. Evaluate reuse or adaptation of SQLite's tokenizer and Lemon grammar before selecting an implementation. SQLite's prepare API is not a public AST interface. Preserve source spans through parsing and translation. Parse complete scripts correctly, including triggers, quoted text, and embedded semicolons. Specify how parsing, name resolution, and schema-dependent validation interact across successive statements.

Track syntactic compatibility separately from semantic support. A valid parsed statement whose behavior is not modeled must produce `UNSUPPORTED`, never silent omission or an unsound approximation.

**Formal semantics.** Develop Lean definitions, inductive execution relations, executable components where useful, and derived lemmas. Avoid a growing collection of independent SQL axioms. Make any unavoidable external assumptions explicit and auditable.

Use SQLite documentation as the behavioral contract and native execution as conformance evidence. Prioritize schema and data migration behavior, including values and coercions, NULL, constraints, DDL/DML, conflict handling, and transactions. Track dependencies such as triggers, foreign keys, collations, and functions explicitly. Model permitted nondeterminism and relevant error outcomes. Declare environmental assumptions and exclusions, including concurrency, resource failures, and crash behavior, in the profile or its fixed, documented settings.

Expand semantic support incrementally, starting with useful end-to-end migration proofs. Unsupported behavior blocks verification. The coverage target is documented SQLite behavior within the declared profile.

**Requirements, interpretation, and proof library.** Expose general predicates over logical states and modeled schemas/executions. Provide interpretation builders for keyed tables, field mappings, and supported joins, with explicit coverage and validity obligations. Supply reusable requirements and lemmas for identity/field preservation, relationships, constraints, unchanged data, permitted transformations, and protected query results. Distinguish current-data validity from enforcement on future writes.

Keep generated obligations stable and inspectable. Supply proof automation for recurring migration patterns without making automated proof discovery a prerequisite for verification. Requirements concerning behavior absent from the model remain outside the supported contract.

**Conformance and coverage infrastructure.** Build this alongside the semantics:

- Import public SQLite test fixtures, preserving setup, statement order, configuration, parameters, relevant API actions, expected results, and assertion rules. Handle query normalization, sorting, hashes, and expected errors faithfully. Track fixtures that depend on unavailable infrastructure; do not assume access to proprietary test suites.
- Execute fixtures on the pinned native engine and construct corresponding formal assertions through the production parsing and translation pipeline. Check those assertions in Lean where supported. Keep native observations and upstream expectations independent of the formal model.
- Check relevant final database state and side effects as well as query output. For unspecified ordering or other nondeterminism, compare against the allowed observation set. Preserve reproducible discrepancies and minimize them where practical.
- Reuse SQLite documentation requirement identifiers to link behavioral claims to definitions, lemmas, fixtures, and proof results. Report grammar coverage, documented-claim coverage, fixture import coverage, semantic support, proved assertions, and native/model discrepancies. Publish denominators and exclusions.

Report proof status, native/model conformance, and coverage independently. Corpus completion must not be represented as semantic completeness or proved native-engine refinement.

**Results and diagnostics.** Exit `0` exactly when all required proofs are accepted for the supplied inputs and supported profile; otherwise exit nonzero. The following labels describe diagnostics, without requiring distinct exit codes or a saved result artifact:

| Result | Meaning |
| --- | --- |
| `VERIFIED` | All required obligations accepted under the implemented model and supplied profile. |
| `VIOLATED` | A requirement is refuted by a checked argument or validated counterexample. |
| `UNVERIFIED` | Proof missing, rejected, incomplete, or resource-limited. |
| `UNSUPPORTED` | Required semantics or execution configuration is unavailable. |
| `INPUT_ERROR` | Invalid input or inconsistent configuration. |

Diagnostics should identify the standing requirement, failed obligation or residual goal, proof/interpretation location, and relevant SQL statements/spans. Explain unsupported profiles, inconsistent inputs, missing interpretation coverage, and unmet preconditions. Include witnesses where available, distinguishing model witnesses from native replays. Do not promise a counterexample or a unique offending statement for every rejected proof. Success needs no output beyond exit `0`.

**Delivery sequence and acceptance.** Include the version-string profile check, parser compatibility, interpretation interfaces, direct checking of one migration's proofs, and the trust policy in the first usable release. Deliver a documented semantic subset, library, CLI, and conformance harness. Expand coverage through documentation/test traceability within the pinned release.

The first release must verify a representative supported migration end to end, including a script with multiple statements. Demonstrate reuse of the same requirements on independently checked examples. Check that the supported profile proceeds to verification and another version fails nonzero. Include valid proofs, witnessed violations, incomplete proofs, unsupported cases, unproved new assumptions, substituted inputs, and attempts to change protected meaning or omit required views. At the first storage-refactoring release, preserve the logical invoice model across changed tables and interpretations; an empty target must fail when protected invoices existed. Define the supported subset and acceptance cases in the implementation plan.

Accept project setup when a fresh checkout can enter the documented development environment and run the standard `just` commands, GitHub Actions runs the same suite and produces usable artifacts, and a version tag produces a GitHub Release with those artifacts. Confirm the requested local/remote repository setup and MIT license. Ship architecture/trust-boundary documentation, supported-profile documentation, and complete single-migration examples. Measure human requirements/binding effort separately from agent interpretation/proof effort and review time.

**Upstream references.** Use version-matched snapshots of [SQLite architecture](https://sqlite.org/arch.html), [documentation requirement traceability](https://sqlite.org/qmplan.html), [testing infrastructure](https://sqlite.org/testing.html), and [SQL Logic Test format](https://sqlite.org/sqllogictest/doc/trunk/about.wiki).
