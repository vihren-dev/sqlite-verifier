**Lean Migration Verifier — Product Roadmap**

Proposal v0.1 · 24 September 2026

This roadmap accompanies the engineering brief. Each step releases a usable migration-verification product with a complete workflow and a bounded guarantee. The releases are cumulative. Only the next release receives a detailed implementation commitment; subsequent releases are hypotheses to revise after each completed step.

**Current boundary (25 September 2026).** Schema and migration SQL are the universal
interface. Examples are source-linked SQL and Lean models, without application
imports, ORM adapters, migration-framework execution or invocation certification.
Profiles contain SQLite semantic settings; application data assumptions belong in
requirements and interpretations. Necessary transaction and data operations must
be explicit SQL with reusable semantics, never implicit framework effects.

“Viable” means a target user can obtain useful results without waiting for a later release. Commercial demand must be validated through adoption and willingness to pay.

| Step | Product | User value |
| --- | --- | --- |
| 1 | Verified SQLite schema extensions | Check routine additions against schema requirements and preservation of existing data. |
| 2 | Verified SQLite table rebuilds | Certify migrations that replace tables while preserving protected information. |
| 3 | Verified data transformations | Check application-specific requirements for backfills and intentional data changes. |
| 4 | Checked execution of certified migrations | Establish approved preconditions on the actual database and apply the exact certified migration. |
| 5 | PostgreSQL edition | Provide the validated workflow for a useful subset of PostgreSQL migrations. |

**Step 1 — Verified SQLite schema extensions.** Target teams using SQLite who want a CI gate for routine migrations, including agent-authored changes. Deliver the agreed SQL/Lean input workflow, requirements library, proof checker, actionable diagnostics, and CI integration.

Start with a small set of operations: creating ordinary tables and adding nullable columns with restricted definitions. Include nonunique indexes only if pilot demand justifies the implementation cost. Certify resulting schema requirements and preservation of existing logical rows and designated column values. State applicability and failure guarantees explicitly. Eligibility depends on both the migration and the existing schema; unsupported constraints, triggers, extensions, or other relevant dependencies block certification.

Full compatibility with the pinned SQLite grammar remains the parser target. Semantic coverage is deliberately narrower. For supported migrations, provide reusable proofs or proof-producing automation so users mainly declare their requirements. Preservation applies to specified data projections; adding a column does not imply unchanged results for every application query.

Completion evidence: a pilot user can verify real schema-extension migrations, adapt requirements through the public library, and repair rejected examples from diagnostics. CI accepts valid proofs, rejects unapproved changes to the approved requirements/preconditions and mismatched artifacts, and reports unsupported cases accurately. CI must identify the approved baseline; legitimate requirement changes follow the human approval workflow. Measure human authoring and review effort against the pilot’s existing workflow.

**Step 2 — Verified SQLite table rebuilds.** Target users whose migrations create a replacement table, copy data, drop the original, and rename the replacement. This is a documented SQLite migration pattern and a useful expansion beyond additive changes.

Initially support direct column copies, explicit column mappings, and a small expression subset. Prove preservation by row identity and protected values, together with target-schema requirements. Account for relevant constraints, indexes, references, and conflict behavior; reject dependencies that remain unsupported. Row counts alone are insufficient. Certify the transaction and failure behavior specified by the execution profile.

Completion evidence: verify a representative real table rebuild over arbitrary admissible initial data. Demonstrate detection of seeded omissions, incorrect column mappings, and identity loss, with replayable witnesses for selected failing examples. A user must be able to adapt the supported pattern without modifying the semantic model. Add reverse-migration proofs here if pilots need them, with an explicit logical restoration relation.

**Step 3 — Verified data transformations.** Target migrations that intentionally change values or strengthen constraints. Start with the highest-demand transformation family observed in Steps 1–2, such as backfilling missing values before introducing a non-null requirement.

Extend the expression and update semantics needed for that family. Provide reusable predicates and lemmas for identity preservation, unchanged fields, permitted value changes, and target constraints. Expand to splits, merges, and relationship changes only when usage supports that choice.

The product remains useful as an offline verifier. It proves the transformation for every database satisfying the approved preconditions and reports those preconditions explicitly. It does not claim that a particular production database satisfies them.

Completion evidence: users express and verify distinct real transformations through public requirements/proof interfaces. A correct intentional change passes; an unintended change to protected information is exposed. Record proof-authoring effort, agent retries, verification cost, and unsupported cases. This release must reduce repeated work through reusable contracts and lemmas.

**Step 4 — Checked execution of certified migrations.** Target users blocked by data-dependent preconditions or uncertainty about whether the deployed artifacts and configuration match the certificate.

Add an optional execution command. Check the actual schema, relevant configuration, artifact identities, and approved executable preconditions; then apply the certified migration under the modeled transaction protocol. Prevent changes between checking the preconditions and applying the migration. Runtime predicates must have a justified correspondence to the formal predicates. Preconditions that cannot be checked remain explicit assumptions and must not be reported as established.

Completion evidence: demonstrate success, precondition rejection, artifact/configuration mismatch, and modeled failure/rollback behavior on representative databases. Tests must exercise attempted interference between checking and application. Crash recovery or automatic retries are included only if their behavior is modeled and covered by the release contract. Reports distinguish proof-checked guarantees, observed runtime checks, and remaining assumptions.

**Step 5 — PostgreSQL edition.** Target PostgreSQL teams with the migration needs validated by earlier releases. Reuse the interface, certificate checking, reporting, and applicable requirements abstractions. Develop a separate PostgreSQL semantic backend and conformance corpus.

Begin with a useful transactional subset under an explicit concurrency profile. Choose the initial operations from pilot migrations rather than seeking SQLite feature parity. Online migrations and coordination with multiple application versions are separate possible expansions.

Completion evidence: a PostgreSQL pilot independently uses the product on real migrations, with engine-specific semantics, diagnostics, and conformance evidence. This step may move earlier if PostgreSQL demand is stronger than demand for the next SQLite expansion.

**Requirements shared by every release.** Ship version/profile pinning, binding proofs to exact artifacts, controlled proof dependencies, and explicit guarantee reporting from Step 1. Develop documentation traceability, native/model conformance tests, and semantic coverage alongside each supported feature. Preserve the distinction between `VERIFIED`, `VIOLATED`, `UNVERIFIED`, `UNSUPPORTED`, and `INPUT_ERROR`. No release may infer universal correctness from corpus coverage or treat a rejected proof as a demonstrated violation.

**Roadmap update after each step.** Completion triggers a review of the shipped product and a new roadmap version. Record:

- What shipped: supported workflows, guarantees, assumptions, exclusions, and remaining defects.
- Product evidence: actual use on migration changes, repeated use, manual bypasses, onboarding/support effort, and willingness to adopt or pay.
- Productivity: human requirements/proof/review time, agent effort and cost, verification latency, and comparison with the previous workflow.
- Technical evidence: unsupported migration patterns, documentation/test coverage, native/model discrepancies, and maintenance cost.
- Decision: continue, narrow, reorder, combine, replace, or stop proposed releases; explain the evidence behind the choice.

Specify the next release’s user, problem, guarantee, exclusions, acceptance examples, and success measures. Estimate its implementation only after this review. Preserve completed releases and their measured results in the roadmap; replace speculative future details as evidence changes. Query-result preservation, richer reverse migrations, SQLite version upgrades, and online deployment verification are candidate directions, not mandatory gates before PostgreSQL.

**Planning rationale and references.** A schema-policy-only release is possible, but the proposed first product already includes a useful data-preservation guarantee. Existing tools such as [Atlas support custom schema and migration policies](https://atlasgo.io/lint/rules), so the additional value of proof authoring must be tested with users. SQLite documents the [table-rebuild procedure](https://sqlite.org/lang_altertable.html) and [transaction behavior](https://sqlite.org/lang_transaction.html) relevant to later guarantees. Implementation must use the pinned version’s documentation.
