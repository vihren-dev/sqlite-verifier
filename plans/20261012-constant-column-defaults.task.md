# Constant defaults for added columns

Created 2026-10-12. Status: IN PROGRESS.
Source: [issue #14](https://github.com/vihren-dev/sqlite-verifier/issues/14).
Specifications: [semantic subset](../docs/semantic-subset.md),
[ADR 0004](../docs/adr-0004-model-conformance-validation.md),
[ADR 0008](../docs/adr-0008-syntax-and-resolution-in-lean.md).

## Outcome

An added column has a literal constant default. Existing rows read the
native-compatible value after the column's affinity applies. An admitted
non-NULL default can be used with NOT NULL. The original projections and
row identities are preserved. The default also supplies an omitted value
where the existing modeled INSERT operation accepts omission.

NULL and non-NULL literals, empty and populated tables, and affinity
boundaries have explicit supported-domain definitions. Nonconstant
expressions and prohibited ADD COLUMN forms remain unsupported. A form
that SQLite accepts but the model does not describe is a model restriction;
it never becomes an invented SQLite execution error.

A NOT NULL DEFAULT example verifies through the real public command and
the offline installed runtime. A changed default, generated term, output
or stored value is detected at the relevant validation boundary. Existing
examples, refutations, JSON statuses and frozen evidence keep their meanings.

## Acceptance

The model suite compares the added value, its storage class and the retained
rows with the exact pinned native engines for NULL, integer, REAL, text
and blob constants and their admitted affinity conversions. It names any
unsupported literal or conversion explicitly. It covers NOT NULL, empty
and populated tables, omitted INSERT values, and rejected nonconstant or
prohibited forms. The native effective settings and source identity are
recorded; the host's system SQLite is not an oracle.

Preservation and default-projection lemmas compile. Public Lean propositions
have checked plain-words documentation and reusable proofs have sketches.
The end-to-end example passes preparation and bundle verification through
actual offline installation on both supported platforms. While the deprecated
source verify command remains, its existing behavior is also checked. Deliberately
changed default data cannot verify the unchanged target. All affected
model, frontend, codec, gate and installed-package checks pass with bounded
processes. The semantic-subset documentation states the admitted behavior.

## Constraints and relevant code

The current column metadata and shared shape are in
`Belay/Sqlite/Declarations.lean` and `Model.lean`. `Table.appendColumns`,
`Execution.step`, `LiteralData` and the schema-preservation lemmas determine
how an added column reaches old rows. Python schema admission and
structural emission are in `belay/sqlite/`; target emission and gates are
application code. Changes must reach their actual callers and tests.

ADR 0008 replaces named statements and schemas with Syntax, the catalog and
Resolved statements. The production resolution switch is delivered. The catalog retains the written
default as Syntax.Expr. PR #115, merged as 780fb214 on 2026-10-14, supplies
storeValue and the Row.Stored invariant. Use these for ADD COLUMN defaults
and preservation; do not add a separate affinity implementation.
Native behavior can be investigated independently. Production changes must
use the accepted representation available when they land and leave no
compatibility path. Preserve T07's single name-free shared table shape.

T08 and T11 are preferred predecessors in the approved queue, not required
ones. Avoid a second implementation of resolution or value conversion.
This task adds no query, trigger, arbitrary-expression or REAL-arithmetic
claim. It does not change the CLI's effective column limit.

The pinned engines accept NOT NULL DEFAULT NULL and the probed nonconstant
defaults on an empty table, although populated tables reject them. The
model must preserve this distinction or refuse the unmodeled form through
its supported-domain check. It must not predict an ADD failure for an
empty table merely to avoid modeling the form.

Default metadata must preserve the source spelling that SQLite reports through
PRAGMA table_xinfo. Blob letter case, whitespace after a sign and identifier
quote delimiters are lost by the current expression tree. Retain that syntax
through the frontend, codec and catalog; do not normalize the judge or copy
recorded observations into predictions. Quoted boolean names must retain enough
information to distinguish them from unquoted TRUE and FALSE.

Default readback for old records must follow SQLite's literal-value path,
which can differ from omitted INSERT values. For example, a TEXT column
reads DEFAULT 1.50 as the text 1.50, and an oversized hexadecimal default
can be read even though INSERT rejects its evaluation. The test suite covers
these boundaries on both pinned engines, without changing INSERT semantics.
Successful default readback preserves the stored-form invariant.

Final owner review is required for column-representation, codec and any
trust-relevant changes. No such production change is made in the native
investigation checkpoint.

## Coordination with independent ADR 0010 work

The owner starts ADR 0010 independently on 2026-10-12. Its team owns case
manifests, Lake orchestration, artifact caches, case seeds and verifier
package moves. T14 reuses those delivered interfaces and adds no second
project reader, compiler driver or cache. Model and proof work can continue.
The final default example uses the delivered belay.toml case layout and
proofs project. Installed acceptance uses prepare and verify-bundle, with
separate verifier and author caches and a no-cache check of the same result.
New checked-in Lean files use the ADR's file categories. Package moves retain
public module names; T14 follows the delivered source and runtime paths.
