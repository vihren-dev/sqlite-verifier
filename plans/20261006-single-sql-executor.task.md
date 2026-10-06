# One SQL executor and generated approved schema

Created 2026-10-06. Status: IN PROGRESS.
Status: [execution record](20261006-single-sql-executor.status.md).
Sources: public issues [#21](https://github.com/vihren-dev/sqlite-verifier/issues/21)
and [#13](https://github.com/vihren-dev/sqlite-verifier/issues/13).

## Required outcomes

The library has one executable script semantics, `runSqlFrom` and `runSql`,
and one contract relation, `ProfileExecutes`. Demonstration, preservation,
Atuin and kernel-test proofs use that semantics. The extension-only `runFrom`,
`run`, `Executes`, its equivalence and composition theorems, and
`Statement.isExtension` are removed with their callers and bridge module.
The contract helpers `of_run` and `congr_run` are removed. New computation
helpers exist only where the migrated proofs need them.

The statement primitive `step`, SQL executor behavior, support obligations,
contract fields and result meanings retain their meanings. Successful examples
remain VERIFIED, the checked refutation remains VIOLATED, and invalid proofs
remain refused. Any preservation law over the SQL executor states the domain
in which its conclusion holds; data writes do not acquire an unconditional
schema-extension guarantee. ProfileExecutes remains available for contracts.

The approved small-example interpretation imports `SchemaInputs` and uses
`Generated.startSchema`. Its protected baseline binds both the schema SQL and
approved source hashes. Every applicable candidate still verifies with that
baseline. A modified protected schema is rejected before proof compilation.
Proof reuse through definitional equality remains valid or is replaced with
an equivalent checked proof.

Changed public declarations have checked Verso documentation. Proposition
restatements include their domains, quantifiers, assumptions and vacuous cases.
Executor docstrings and ADR 0004 describe the single current semantics;
historical evidence and model/profile support are unchanged.

## Behavioral verification

- Compile the library, all demonstrations and migrated Atuin/kernel proofs.
  A source search and import checks find no removed execution API or bridge.
- Run `just test`, including source, kernel, bundle, Atuin and upstream cases.
  Run the affected full model/conformance target and verify unchanged traces,
  failure positions, transaction outcomes and supported-domain obligations.
- Verify every small example through its protected baseline with the generated
  schema binding. Check the positive, refutation and permitted-failure paths.
  Alter `schema.sql` and verify rejection before proof compilation.
- Run actual installed-runtime examples and attack checks against the changed
  library and approved inputs. Required final owner review covers the contract
  helper and protected-baseline changes; acceptance records identify exact
  revisions, tests and artifacts.

Tests and subprocesses have explicit timeouts. This task adds no SQL syntax,
executor categories, new profile settings or new frozen corpus version.

## Constraints and relevant source

`Execution.lean` also owns the statement/error/outcome types and `step`.
Those remain after its extension executor is deleted. `SqlExecution.lean`
tracks committed and visible state separately. Script composition and additive
preservation facts must reflect its actual state and stopping behavior.
`SupportedSql` is a checked contract obligation, not an assumed premise that
may disappear during convenience-helper migration.

Relevant consumers include `Demonstration`, `ReverseDemonstration`,
`FailureDemonstration`, `Examples`, `Preservation`, `Contract`,
`examples/atuin/AtuinFacts.lean`, `examples/atuin/Proofs.lean` and
`tests/kernel_gate/Proofs.lean`. Root imports and Nix source selections must
follow bridge-module deletion. Atuin's historical origin named `legacy` is
data, unrelated to the removed executor.

`examples/approved/Interpretation.lean`, its `baseline.json`,
`migration_check/baseline.py`, baseline tests and `docs/source-staging.md`
define the generated starting-schema pattern. Protect the source SQL as well
as approved module contents. Preserve frozen v1–v5 and historical receipts.
