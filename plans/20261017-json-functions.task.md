# Further JSON functions, slice 6c of ADR 0012

Created 2026-10-17. Status: DONE (pull requests #146 and B).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), "Amendment 5", "Further
JSON functions (slice 6c)", with the owner decisions of 2026-10-16 (#141). Related: slice
6b ([task](20261016-json-extract.task.md)), whose reading, paths, rendering and failure
rules this slice uses; slice 6d (`json_each`) follows.

## Pull requests

- **Pull request A (subject):** the four functions in Lean, their resolution, examples,
  authored coverage cases, mutants and a corpus writer. No change under `judge/` or
  `integrity/`.
- **Pull request B (judge, owner approval):** the coverage corpus (version 23) is frozen
  and claimed, and cases that newly agree are added to `mustAgree`.

## Outcome

1. **`json_type(json [, path])`.** The type of the whole JSON value, or of the value at
   the path: `null`, `true`, `false`, `integer`, `real`, `text`, `array` or `object`, as
   TEXT. A number without a fraction or an exponent is `integer`, also beyond 64 bits
   (`9223372036854775808`) and in hexadecimal (`0x1F`); `1e400` is `real`. A path that
   selects nothing, a NULL JSON argument and a NULL path give NULL.
2. **`json_valid(json [, flags])`.** 1 or 0, never `malformed JSON`. Without flags, or with
   flags 1, only RFC 8259 JSON text is valid (`{a:1}`, `[1,]` and comments give 0); flag
   2 also accepts JSON5. A text argument is never valid JSONB, so flags 4 and 8 alone give
   0. The flags are the integer value of the argument (`'2'` and `2.5` are 2); a value
   outside 1 to 15 (also NULL, `'x'` and a BLOB) is the error
   `FLAGS parameter to json_valid() must be between 1 and 15`, while the statement runs.
   A NULL JSON argument gives NULL.
3. **`json_array_length(json [, path])`.** The number of elements of the array, or 0 for
   any other value; NULL for a path that selects nothing.
4. **`json(json)`.** The rendered JSON text of slice 6b: no whitespace, numbers and string
   escapes as written, JSON5 forms normalized, and duplicate keys kept. NULL gives NULL.
5. **Errors.** Malformed JSON (except for `json_valid`) and a bad path are the errors of
   slice 6b, with the same rules for where the model reports them. A call with a wrong
   number of arguments (`json_type` with three, `json_valid` with three, `json` with none
   or two) is SQLite's prepare error `wrong number of arguments to function %s()`.
6. **Arguments.** INTEGER and REAL arguments are read as their text, as in slice 6b. A
   BLOB JSON argument stays a model restriction for every function.
7. **Verification target.** `Contract.lean` does not change; every write keeps
   `Conforms`. Expressions without the new functions keep their current semantics.
8. **Evidence.** Authored coverage cases agree with native SQLite 3.51.0 and have kernel
   proofs; each mutant below changes a verdict; the verdict counts of the claimed corpora
   do not go down.

## Tests

- Lean examples: each type name; `json_valid` of JSON, JSON5 and malformed text under
  each flag kind; the flags error; array lengths of arrays, objects, scalars and missing
  paths; `json` of whitespace, JSON5 and duplicate keys.
- Authored coverage cases (native SQLite as the oracle): each item of the outcome, the
  functions in `WHERE`, `SET` and `VALUES` and over a table column, and the prepare error
  of a wrong argument count. The upstream `json101`, `json102` and `json501` cases that
  agree are the second check.
- Mutants, each changing the verdict of an authored case: a large integer typed `real`;
  `json_valid` accepting JSON5 without flag 2; `json_valid` failing on malformed text; the
  flags error ignored; `json_array_length` of an object as its member count; `json`
  returning its argument as written (re-rendering numbers is the mutant of slice 6b).

## Key points for the implementer

- **Reading.** `json_valid` needs to know whether the text is strict JSON; SQLite tracks
  whether the reader met a JSON5 form (`jsonParseFuncArg`, `JsonParse.hasNonstd`). The
  port of slice 6b reads JSON5 and must report this without a second reader.
- **Failures.** The flags error is a new kind of function failure. It follows the rules
  of `JsonFaults.lean` (certain only in a query without `FROM`, otherwise unsupported for
  the data); `describedFailure` must include it.
- **Native probing.** The sqlite3 shell converts `\uXXXX` in its input before SQLite reads
  it; build backslashes with `char(92)` or check through the library (the recorder). This
  is why the ADR's escape example for slice 6b was wrong; it is corrected with this task.
- **Kernel and mutant cost.** Slice 6b grew `tests.mutants` by about 36 s; keep the new
  mutants few and the cases small.
