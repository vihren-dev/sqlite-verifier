# SQL-only core cleanup status

Created: 2026-09-25. Status: DONE (implementation and local validation).

Task: [sql-only-core.task.md](20260925-sql-only-core.task.md).
Authority: owner's explicit SQL-file universal-interface correction, 2026-09-25.
Starting revision: d6c46ef1. Lean toolchain is pinned by lean-toolchain; the Nix
environment stays isolated in nix/. No framework or application execution is a
product requirement. Owner review of application meaning remains separate from
mechanical validation.

Progress: audited the profile-to-execution coupling; preparing source-backed SQL
example and removal of SQLx semantics, capture infrastructure and documentation.
Validation: pending implementation. No claim of equivalence or passing tests yet.

2026-09-25 environment and scope cleanup: removed the Rust/Cargo capture shell,
capture recipes and runner-specific CI artifacts; retained pinned SQLite tools,
small Nix source boundary and resource checks. Brief/roadmap now state the SQL-only
boundary. Prior runner task is explicitly superseded; historical capture/review
documentation points to the current example instead of asserting obsolete results.
Seven resource/CI-routing regressions pass. Real Nix source regression passes in
Git-parent and non-Git directories: 2,944-byte source stays identical after changes
to dist/, build/, .lake/ and workspace metadata. Full checks await component cleanup.

Current interface agreement: profiles are SQLite versions only (`sqlite351`,
`sqlite346`). The example uses explicit BEGIN, ALTER, literal INSERT, COMMIT and
literal UPDATE. A documented timestamp/duration instantiate runtime values;
no framework-wide equivalence is claimed. The reasonable baseline precedes
optimizer-created statistics tables. Source review confirms missing or NULL
shell decodes to no recorded shell; preserving old stored fields preserves
decoder inputs, without claiming a formalization of every application query.

Core review checkpoint: reusable literal DML explicitly checks lossless affinity,
integer/NULL key comparisons, constraint validity and deterministic rowid allocation.
Open-transaction outcomes distinguish persisted and visible storage. Old additive
proof conveniences require a syntax guard before entering the generic semantics.
The semantic-subset document records those restrictions. Markdown checks pass;
Lean and example proof validation remain in progress in the formal workspace.

Packaging cleanup: Lake retains compiled files when their source modules are
deleted. The runtime archive now selects artifacts from the current project
source-module inventory and rejects an unbuilt current module. A regression
checks that an obsolete .olean is excluded while current kernel-private and IR
files are retained. Six packaging/resource regressions pass in the pinned shell.
This does not delete unrelated build outputs or caches.

Integrated conformance tip 14e8e958 (base unit 7cf73a25). Six ordinary native
SQL cases and seven fresh-receipt/coverage regressions independently reproduced
in the root pinned shell. Removed the Rust application/framework capture tree,
vendored application migrations and old model trace adapters. The example README
links pinned upstream code and explains concrete runtime values and scope.
Coverage distinguishes native observations from formal proofs. Local Markdown
links resolve. Generic core and frontend integration remain pending.

## Generic formal core checkpoint

Removed RunnerProfile, RunnerExecution and RunnerFootprint. Profiles now contain
only the pinned SQLite version. The supplied Statement syntax includes explicit
BEGIN/COMMIT/ROLLBACK, full ordered literal INSERT and single-literal UPDATE under
an integer equality predicate. No framework inserts, timing updates, optimizer
writes or rollback are inferred. Outcome.pending exposes both the committed
snapshot and visible connection storage, including the failing statement index.

LiteralData admits identity affinity conversion, INTEGER/NULL unique-key
comparison, ordinary nullable primary keys, NOT NULL and ABORT constraints.
Ordinary rowid allocation is exactly empty=1 or largest+1, including negative
largest identities; random allocation at the signed maximum is excluded by an
explicit checked support obligation. Every reached DML statement must satisfy
the generic data domain. Initial Admitted includes schema conformance, widths
and distinct signed rowids. The additive proof helpers additionally require an
all-extension syntax guard and the CREATE/index namespace guard, so their legacy
invalid-statement result cannot certify DML or transaction behavior.

Validation in the existing pinned tiny Nix shell: `timeout 90 lake build
SqliteVerifier` passed 21 jobs, including finite kernel assertions for complete
transactional writes, nullable keys, negative rowids, ABORT with a pending ALTER,
explicit rollback, open-transaction EOF, invalid transaction control, unsupported
coercions and the rowid-allocation boundary. Existing ordinary, reversed and
allowed-failure universal proofs retain only propext/Classical.choice/Quot.sound.
`timeout 360 python3 tests/kernel_gate_test.py` passed honest proofs/refutations
and all adversarial rejection cases, including a candidate 3.51 convenience
target attempting to substitute for sealed 3.46 input. The gate reconstructs the
same complete argument list; no generated-target alias is trusted.

This is a bounded core unit, not completion of the task or a native refinement
claim. The revised Atuin example proof and generic SQL/native comparisons remain
in progress. Old Atuin Lean files are intentionally not counted as checked at
this checkpoint. Their replacement must retain six-prior to seven-successful
catalog identities in example-only before/after invariants, alongside arbitrary
admitted history and exact old bookkeeping preservation. No application catalog
belongs in the core or execution profile.

Root integrated 914188f4 and independently built the library and proof checker:
24 jobs passed (`build/sql-only-core-build.log`). Source review covered the generic
data domain, transaction outcomes and guarded legacy bridge; no blocking finding.
Removed 15 exact generated artifacts for the three deleted modules from the root
workspace's library directory. No unrelated cache or generated files were deleted.

Independent conformance review of 914188f4 found no concrete model/source or
vacuity blocker: admitted-state witness, reached-statement support, total outcomes,
nullable uniqueness, negative/MAX rowid boundaries and open-transaction ABORT
behavior were checked. Structural-example comments now describe generic SQLite
regressions rather than the retired capture pipeline (comment-only change).

Integrated frontend 76f75eec: only supported SQLite version strings select the
profile; literal transaction/data statements are emitted from supplied SQL.
No application/framework references remain in the production Lean or Python
frontend source. Root independently passed emitted Lean schema/execution checks
and 13 profile/write/schema-translation tests. Component evidence also includes
the full legacy CLI suite. Aggregate coverage is running; the revised Atuin proof
bundle and its public CLI negatives remain pending.

Aggregate coverage exposed one stale generated assertion path: it still called the
legacy DDL evaluator and lacked the new pending-outcome constructor. Updated the
shared comparison generator to use public runSql, prove SupportedSql admission,
and assert closed outcomes for its existing fixtures. The focused bounded
native/model comparison passed (exit 0, build/sql-only-model-comparison.log).
The failed aggregate report is not treated as passing evidence; rerun follows
final example integration.

Integrated the source-linked README follow-up d5bac0ce and made the documented
transaction syntax match admission: deferred BEGIN and COMMIT/END/ROLLBACK only,
without named transactions, other locking modes or savepoints.

Aggregate conformance now passes (`build/sql-only-coverage.log`, exit 0).
Rewrote AtuinFacts for the two-table SQL-only example and six/seven-record
interpretation invariants. Retained explicit kernel-checked equality of generated
starting/resulting schemas to the reviewed helper definitions; removed the old
SQLx input binding. Arbitrary-row ADD preservation and both representation
soundness proofs compile against isolated exact snapshots of the lead's revised
approved files and production-generated SqlInputs (`build/sql-only-facts`).
These component proofs do not yet constitute the complete example certificate.

Owner clarified and authorized the intended architecture: a separate typed History
business model, schema-pinned interpretations, business-level requirements and no
handwritten duplicate complete schema. Updated the task and engineering brief.
The previous storage-projection example rewrite is superseded; its generic SQL
lemmas and tests remain useful. Formal lead owns the corrected example; integration
owns sealed starting-schema staging; conformance owns source fidelity and adversarial
review. Core regression batch passed: generated schema, kernel gate, compilation
isolation, legacy CLI and 35 unit tests (build/sql-only-core-regressions.log, exit 0).
The whole revised example is still pending; prior component proofs are not claimed
as evidence for its new business contract.

The target-owned baseline CI now supports an optional exact schema.sql hash,
preserving the reviewed schema/interpretation pair after removal of the handwritten
schema copy. Local immutable-Git tests pass for all three configured example roots,
including changed schema and schema-symlink rejection, with existing source,
manifest and candidate-checker protections retained. Driver-side optional schema
hash enforcement is a separate integration component pending merge.

Independent gate now seals/replays generated schema and SQL inputs before approved
project declarations, then candidate declarations. Kernel fixtures split SchemaInputs
from SqlInputs and use the generated schema in the approved interpretation. The
complete bounded gate suite passed (build/business-gate-tests.log, exit 0), including
substitution of Generated.startSchema from candidate and approved source. The
approved substitution is rejected already by Lean import conflict; the test accepts
that earlier rejection as well as protected replay rejection. Existing positive,
refutation, initializer, forged-body, axiom and profile-substitution cases still pass.

Integrated frontend staging0046f2a2 with checked gate6ec109ad in03e5f7c6. Root
independently passed real sandbox compilation/gate tests and both optional-schema
baseline suites (build/business-staging-tests.log and business-baseline-tests.log).
Source review of the revised model boundary finds business History separate from
SQLite, Q as business equality, actual canonical decoder checks on results, and
migration catalog facts confined to representation invariants. The generated
schema helper only performs lookups and derives the expected nullable extension.
The complete example proof and final CLI/package validation remain pending.

Integrated formal a84483b6, business model/README98c356be and conformance emitter
repair c9a81caa. Resolved the single AtuinFacts conflict to the lead's new typed
version, superseding the earlier storage-view soundness helper. Root built all
25 library/checker jobs and independently ran the public Atuin CLI with the
proposed baseline: VERIFIED, five statements, SQLite3.46.0, exact seven approved
module hashes and schema.sql hash (build/business-atuin-verified.json). Both
technical-lead and independent conformance source reviews accept the final
universal proof and nonempty typed witness, with only allowed foundational axioms.
README now reports this actual proof result and includes baseline enforcement.
Negative CLI and installed-runtime checks remain pending; no owner acceptance
or hosted-platform validation is inferred from the local result.

Integrated checked CLI harness f250a962: one positive plus13 negative cases pass,
with real rejection diagnostics distinguished from timeout. The aggregate check
batch also passed: pinned toolchain smoke, fresh grammar/native/model/Atuin SQL
coverage, both environment-source identity variants (2944bytes unchanged), parser
cache/reuse checks, seven coverage-unit checks and36 unit tests. Generated-schema,
compilation/gate and ordinary CLI checks passed at their component checkpoints.
The runtime archive was rebuilt once (974MiB) after a successful space preflight;
installed offline/isolated entrypoint and typed Atuin checks are now running.

Completed: 2026-09-25. Final implementation checkpoint19266332 plus this status
update. The rebuilt974MiB aarch64-darwin archive installed offline and passed the
actual isolated executable's ordinary positive/refuted/unsupported checks plus
typed Atuin verification and all13 negatives (build/business-installed-runtime.log,
exit0). Ambient Python/Lean settings were poisoned and build tools removed from
the installed check's PATH. This validates the delivered runtime, not just source
compilation. The archive was built once; no global cache/database/volume cleanup
was performed. The small Nix environment source remains2944bytes.

All required engineering work for this correction is complete: SQL-only boundary,
typed business History and equality requirement, schema-generated interpretation
binding without a handwritten copy, example-only migration invariants, generic
SQL semantics, protected schema/source input checks, source-backed README, universal
model proof, adversarial checks and installed runtime. Independent reviews found
no concrete correctness/vacuity blocker. The application contract remains proposed
for owner review; Step1 product acceptance and publication to protected public main
are separate, not inferred from passing tests. This change was checked locally on
aarch64-darwin; no new hosted Linux run is claimed.
