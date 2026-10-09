import Belay.Sqlite
import SqliteVerifier.Contract
import SqliteVerifier.Library
import SqliteVerifier.NullableProjection
import SqliteVerifier.ApplicationKeys
import SqliteVerifier.ApplicationKeyPreservation

set_option doc.verso true

/-!
Import this module to use the stored-data model, logical contracts and reusable
schema proofs. A certificate establishes the written model obligations;
native SQLite conformance is assessed separately.

Start with {name}`Belay.Sqlite.Column` and {name}`Belay.Sqlite.Schema`.
The optional column fields have plain defaults. A valid schema has a finite
empty-data witness, useful when proving nonempty admission:

```lean
open Belay.Sqlite SqliteVerifier
example : Conforms [] (Schema.emptyDatabase []) :=
  Schema.emptyDatabase_conforms (by simp [Schema.Valid])
example : Column.plain { name := "id", affinity := .integer } = true := by rfl
```

Choose the observation and change relation explicitly. Use
{name}`SqliteVerifier.projectedInterpretation` and
{name}`SqliteVerifier.LogicalContract.preservation` when physical rowids and
stored row order matter.

For a different policy, construct {name}`SqliteVerifier.Interpretation` and
{name}`SqliteVerifier.LogicalContract` directly. Their invariant, observation,
validity, change, schema, failure and applicability fields remain the general
interface. Supply {name}`SqliteVerifier.requiresSuccess` when open transactions
and failures must be excluded by the proof.

The target is {name}`SqliteVerifier.VerificationConditions`: a starting witness,
sound before/after/failure representations, the starting invariant, support for
every admitted database, and applicability plus result obligations for every
related outcome. {name}`SqliteVerifier.VerificationConditions.of_runSql` lets
users prove those outcome obligations from the computed SQL result while
retaining the universal support premise. {name}`Belay.Sqlite.SchemaOnly`
guards the current schema-extension preservation laws.

Engineering examples and demonstrations are test code in the separate
`EngineeringExamples` library. This module does not import them.

For command-line verification, supply approved schema, requirements and current
interpretation files, plus candidate SQL, next interpretation and proof files.
Preparation binds those exact inputs to the generated target; the checker then
checks the exported certificate. CLI help describes command options and result
codes. A library theorem alone does not bind an arbitrary candidate file.
-/
