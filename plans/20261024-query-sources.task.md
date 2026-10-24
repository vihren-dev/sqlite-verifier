# Queries as sources: derived tables, ordinary CTEs and views

Created 2026-10-24. Status: OPEN. Implementation follows task review and a clean
S4 boundary with disjoint file ownership.
Status: [status file](20261024-query-sources.status.md).
Specs: [ADR 0019](../docs/adr-0019-guide-sql.md), D5 and slice 4, plus D3's
compound-subquery metadata exception; ADR 0018 query semantics; ADR 0017 S6.
Base inspected: `vihren-dev/sqlite-verifier`, PR #239, commit `98a07bfe`.

## Scope and owner decision

The model has a `Source.subquery` placeholder and the text layer refuses derived
tables. Derived tables, ordinary CTEs and views must use one resolved query-source
meaning. This is the prerequisite for ADR 0019 slice 5, whose ALTER statements
rewrite views, and for the S6 rebuild proof. Scope is the complete D5, not only
the source form needed by one guide example.

On 2026-10-24 the owner chose nonrecursive CTEs only: reject actual recursion
even without the `RECURSIVE` keyword, and retain the exclusion of that keyword
even when a CTE is nonrecursive. SQLite's acceptance of recursion without the
keyword is the reason for the semantic check. `MATERIALIZED` and
`NOT MATERIALIZED` hints and `INSTEAD OF` triggers remain outside scope.

## Required outcomes

1. **Derived sources work through every layer.** A supported SELECT in FROM or
   JOIN supplies its result rows and metadata to the containing query. SQL text,
   model resolution/evaluation, codecs, the conformance runner and the public
   `sql`/`db!` surface support it. This includes aliases, qualification, star
   expansion, nested sources, aggregates, DISTINCT, compound queries and supported
   LIMIT/OFFSET forms. Existing inner/left/right/full joins use their usual
   conditions and NULL extension. A derived table has no implicit rowid.
2. **Names and metadata match SQLite.** Derive every output column's name,
   affinity and collation, including duplicate names, explicit COLLATE and
   compound terms. Reuse the existing derived-name rules. Derived-column
   metadata is distinct from scalar and IN-subquery metadata. Implement the D3
   exception currently refused as `compound-subquery-column`: a non-UNION-ALL
   compound with ORDER BY COLLATE can use SQLite's derived-table rewrite. Its
   IN comparison reads the derived column; its scalar form still has no
   collation. Existing ordinary compound IN rules remain unchanged.
3. **Scope is exact.** Resolve source names, column names, aliases and nested
   outer references with SQLite's shadowing and error precedence. A derived
   source may read a permitted enclosing-query binding, but it cannot read a
   sibling FROM source as a LATERAL reference. Existing ON/USING/NATURAL and
   function-source rules keep their meaning. Name resolution must not depend
   on an arbitrary traversal order chosen for implementation convenience.
4. **Ordinary WITH works.** Support nonrecursive CTEs, explicit CTE column lists,
   nested/shadowed names, multiple references and forward references to other
   CTEs. WITH can scope a supported SELECT or supported INSERT/UPDATE/DELETE
   form where SQLite permits it; this does not bring INSERT SELECT ahead of
   slice 5. The definition is evaluated through the same query-source machinery.
   Recursion detection follows resolved references, not a textual self-name
   search or just the keyword. Refuse valid recursive SQL as a model restriction;
   preserve SQLite errors for invalid circular references and invalid column
   counts. Both materialization hints remain explicit model restrictions.
5. **Views are catalog definitions.** CREATE VIEW, CREATE VIEW IF NOT EXISTS,
   DROP VIEW, DROP VIEW IF EXISTS and view sources have their SQLite behavior,
   including optional output-column lists, object-name conflicts and prepare
   errors. A view stores unresolved query syntax and resolves it when used.
   CREATE VIEW may succeed before its referenced table exists. Dropping or
   changing a referenced table affects later uses; a view must not retain a
   stale catalog position. Nested views and view cycles have the correct
   behavior. Writes to views remain errors where SQLite needs an INSTEAD OF
   trigger; this task does not add such triggers. Catalog/storage invariants
   account for views without inventing table rows for them.
6. **One execution context.** Sources reuse the existing evaluator's parameters,
   clock, counters and outer cells. A source does not reset the context or read
   a fresh clock. Prepare errors, evaluation failures and model restrictions
   propagate without being mistaken for empty rows. If a source's possible
   plans change which result rows it contains, the containing statement is
   unmodeled, as D5 requires. Never choose one arbitrary permitted result to
   materialize a plan-sensitive source. Mere row-order uncertainty follows
   existing query rules; it is not a new promise of a canonical order.
7. **Existing proofs remain usable.** The admitted/valid database invariants
   and their statement/run theorems cover the new view catalog/statement forms.
   Existing query laws and S4 surface proofs compile. Extend stable source-row
   and query-output contracts as needed rather than cloning query interpreters
   for each spelling. Keep text imports at the public parsing/codec boundary;
   translator code must not acquire proof-only imports. This task adds no VM,
   alternative relational language or generic plugin framework.
8. **Conformance is explicit.** Authored native cases and kernel proofs cover
   the new behavior. Model restrictions stay restrictions, never fabricated
   SQLite errors. Preserve current claimed agreement and identify any new
   claims from measured verdict results. Update public docs and the ADR's
   implementation record with the delivered scope and remaining restrictions.

## Tests and acceptance

- Kernel examples cover derived sources first and in joins, all supported outer
  joins, NULL extension, empty sources, qualification/star expansion, duplicate
  names, parent/outer binding, forbidden sibling binding, aggregate/DISTINCT
  sources, compound metadata and LIMIT/OFFSET certainty.
- Include multi-column metadata examples, not only first-column comparisons:
  parent TEXT affinity, NOCASE/BINARY overrides and compound expressions with
  different types. Exercise D3's IN and scalar ORDER BY COLLATE exception.
- Source context tests use bound parameters, a supplied clock and connection
  counters, plus nested scalar/IN queries. A division or expression failure and
  a plan-sensitive LIMIT source cannot silently become an empty source.
- CTE cases include forward references, nested name shadowing, explicit column
  lists, reused CTEs, CTEs attached to each supported statement family and an
  unused definition according to SQLite's preparation behavior. Check direct
  and indirect recursion without the keyword, nonrecursive WITH RECURSIVE,
  invalid circular references and both materialization hints.
- View cases include CREATE before the referenced table exists, later success,
  later missing-table failure, changed catalog positions, nested views, cycles,
  name collisions, IF EXISTS/IF NOT EXISTS and optional column names. Check
  DROP/rollback and admitted/valid preservation for the actual resulting state.
- Text tests check source spans, parameter numbering and error/restriction
  categories. Nix-selected surface fixtures use `sql`, `db!`, query predicates
  and proved validity after CREATE/DROP VIEW. Axiom audits retain existing rules.
- Add a small authored native corpus through the existing recorder and judge
  workflow. Kernel-checked verdicts cover the observable cases above. Targeted
  mutants cover scope, column affinity/collation, uncertainty propagation and
  recursive-reference detection; run only those relevant mutant names with `-k`.
  New corpus/claim/lock changes go in a separate judge PR needing owner approval
  before merge. Inspect existing claims; do not assume this syntax is absent.
- Record frozen predictions before model edits. At completion, classify each
  changed prediction, preserve every current mustAgree claim and record measured
  gains. A lexical count of SQL syntax is not a conformance gain.
- Every new test has a finite timeout and real Nix suite registration. Each
  coherent commit has targeted checks, the package dev build and independent
  review. Each acceptance part ends with `just test-full` and `just verdict`;
  task end also runs `just test-nix` and `just test-scheduled-checks`. The owner's
  override is recorded in [the build-boundary status](20261024-text-build-boundaries.status.md).
  Only Nix results are acceptance evidence in status files and PRs.

Three acceptance parts: derived sources and D3's metadata exception; ordinary
CTEs; views and their preservation laws. These partition the outcomes, not the
implementation steps. Slice 4 is complete only when all three pass.

## Existing code and constraints

Model paths below are under `packages/belay-sqlite-model/Belay/Sqlite/Model/`:
`Resolution/SyntaxExpr.lean`, `Resolution/QueryForm.lean`,
`Resolution/SourceList.lean`, `Resolution/SubqueryResolution.lean`,
`Resolution/SubqueryShapes.lean`, `Resolution/CompoundNames.lean`,
`Resolution/CatalogObjects.lean`, `QueryFunctions.lean`, `Subqueries.lean`,
`Codec/SyntaxJson.lean` and the statement/validity laws.
Text translation is in `packages/belay-sqlite-text/Belay/Sqlite/Translation/`,
especially `Sources.lean`, `Select.lean` and `Subqueries.lean`.
Pinned native source is `parser/upstream/sqlite3.c`: `sqlite3SubqueryColumnTypes`,
`sqlite3ColumnsFromExprList`, `sqlite3CreateView`, `sqlite3ViewGetColumnNames`
and `selectExpander` provide relevant behavior.

`SourceList` already separates source metadata from pending ON expressions.
The indexed query list carries expression subqueries and context. Derived
sources need metadata for every column, while `SubqueryShape` currently has
first-output metadata. Catalog positions change on DROP; stored unresolved
view syntax is also necessary for slice 5's later ALTER rewrites.

Do not implement slice 5 concurrently against a different view/catalog design.
Reserve shared model barrels, query laws and statement cases before starting.
If exact SQLite behavior contradicts this task or a needed capability changes
its meaning, report the specification finding and obtain the owner's decision;
continue independent work while that decision is pending.
