# JSON reading and json_extract, slice 6b of ADR 0012

Created 2026-10-16. Status: open.
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), "Amendment 5", "JSON
reading and `json_extract` (slice 6b)", with the owner decisions of 2026-10-16 (#141).
Related: slice 6a ([task](20261016-select-without-from.task.md)), whose queries without
`FROM` the cases use; slices 6c and 6d use this slice's reading and rendering.

## Pull requests

- **Pull request A (subject):** the JSON value model, reading, path evaluation and
  rendering in Lean, resolution of the function and operators, examples, proofs,
  authored coverage cases, mutants and a corpus writer. No change under `judge/` or
  `integrity/`.
- **Pull request B (judge, owner approval):** the coverage corpus (version 22) is frozen
  and claimed, and cases that newly agree are added to `mustAgree`.

## Outcome

1. **Forms.** `json_extract(json, path, ...)` with one or more paths, and the operators
   `json -> path` and `json ->> path`, in every expression context that the model has
   (queries, `SET` values, `VALUES` items, conditions).
2. **Reading.** JSON text and JSON5 text, as SQLite reads them: whitespace and comments,
   unquoted keys, single-quoted strings, hexadecimal numbers, `+` and leading or trailing
   decimal points, `Infinity` and `NaN`, and trailing commas. A TEXT, INTEGER or REAL
   argument is read as its text. A NULL argument gives NULL. A BLOB argument (JSONB) is
   a model restriction.
3. **Paths.** `$`, `.label`, `."quoted label"`, `[n]`, `[#]` and `[#-n]`, as SQLite reads
   them; any other path is `bad JSON path: '%s'`. A path that selects nothing gives NULL.
   On the right of `->` and `->>`, a bare label is `$.label` and an integer is `$[n]`.
   Of duplicate keys, the first one is selected.
4. **Values.** A selected JSON scalar is an SQL value: an integer within 64 bits as
   INTEGER, any other number as REAL (`1E400` is `Inf`), a string as TEXT with its
   escapes decoded, `true` and `false` as 1 and 0, `null` as NULL. An object or an array
   is its rendered JSON text. Several paths give the rendered JSON array of the
   selections. `->` gives the rendered JSON text of the selection, also for a scalar.
5. **Rendering.** Rendered JSON text is SQLite's: no whitespace, numbers as written
   except JSON5 forms, which are normalized (`0x1F` is `31`, `.5` is `0.5`, `Infinity` is
   `9e999`, `NaN` is `null`), and strings with SQLite's escapes (checked natively:
   `é` is decoded, `\n` and `\"` stay escaped).
6. **Errors.** Malformed JSON is `malformed JSON`, and a bad path `bad JSON path: '%s'`,
   both while the statement runs; the statement fails as ABORT.
7. **Verification target.** `Contract.lean` does not change; every write keeps
   `Conforms`. Expressions without the new forms keep their current semantics.
8. **Evidence.** Authored coverage cases agree with native SQLite 3.51.0 and have kernel
   proofs; each mutant below changes a verdict; the verdict counts of the claimed corpora
   do not go down.

## Tests

- Lean examples: each value kind; each path form; missing paths; several paths; `->`
  and `->>` with a path, a label and an integer; duplicate keys; JSON5 forms and their
  rendering; escapes; both errors.
- Proofs: the reader on rendered text gives the same value (round trip) for the JSON
  that the renderer emits; a write with a JSON value keeps `Conforms`.
- Authored coverage cases (native SQLite as the oracle): each item of the outcome,
  `json_extract` in `WHERE`, `SET` and `VALUES`, and over a table column; the upstream
  `json101` cases that agree are the second check.
- Mutants, each changing the verdict of an authored case: `true` as text; a scalar of
  `->` without quotes; the last duplicate key selected; numbers re-rendered; JSON5 not
  normalized; `[#-1]` as the first element; a missing path as an error.

## Key points for the implementer

- **Size.** This is the largest slice of Amendment 5. SQLite's JSON code
  (`json.c`, `jsonTranslateTextToBlob`, `jsonReturnFromBlob`, `jsonAppendString`) is the
  reference for reading and rendering; check every rule natively, one statement per
  line (the sqlite3 shell skips the rest of a line after an error).
- **Errors at run time.** Today query evaluation has one run-time error
  (`integer overflow`, `Query.fails`); writes have constraint errors. JSON errors can
  arise in any expression; evaluation reports them without a second evaluator (for
  example one evaluator in `Except`, with today's total `eval` derived from it).
- **Which expressions SQLite evaluates** (checked natively): it short-circuits
  (`0 AND json_extract('{bad', '$')` is 0, no error), folds `X AND 0` to 0 without
  evaluating `X`, does not evaluate rows beyond `LIMIT`, and with `ORDER BY` evaluates the
  result columns only of the returned rows but the `ORDER BY` keys of every row. So an
  error is part of the outcome only where SQLite surely evaluates the expression: outside
  `AND`, `OR` and `COALESCE`, in the `WHERE` of every source row, in the `ORDER BY` and
  `GROUP BY` keys and aggregate arguments of every row that reaches them, and in the
  result columns of the returned rows. Any other possible error makes the statement
  unsupported for that data (its `statementReady` is false), as the model does not
  describe SQLite's code generation.
- **Numbers.** Reading a JSON number to REAL must use the conversion that the model
  already has for text (`NumberConvert.lean`), so that `1.5` is the same double.
- **Frontend.** The operators `->` and `->>` are parser tokens (`PTR`); function calls
  of two or more arguments are `callPair` today, so `json_extract` with several paths
  needs a call form with a list of arguments.
- **Kernel and mutant cost.** JSON terms make kernel proofs larger; keep authored cases
  small and measure the model and mutant suites. CI's `test-full` has little headroom.
