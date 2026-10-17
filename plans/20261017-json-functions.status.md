# Further JSON functions, slice 6c of ADR 0012: status

Created 2026-10-17. Status: open.
Task: [20261017-json-functions.task.md](20261017-json-functions.task.md).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), Amendment 5, "Further JSON
functions (slice 6c)".

## Relevant files

- JSON port: `packages/belay-sqlite/Belay/Sqlite/Json/` (`Read.lean`, `Extract.lean`,
  `JsonApply.lean`, `Node.lean`).
- Resolution: `Resolution/Calls.lean`, `Resolution/QueryForm.lean` (`JsonFunction`).
- Failures: `JsonFaults.lean`, `JsonReady.lean`.
- Cases: `conformance/authored_json.py` (slice 6b) as the pattern.

## Progress

- 2026-10-17: task and status files, stacked on #145 (slice 6b, PR B). Native facts
  checked on SQLite 3.51.0, one statement per line: the type names; `9223372036854775808`
  and `0x1F` are `integer`, `1e400` `real`; `json_valid` without flags rejects JSON5 and
  comments, flag 2 accepts them, flags 4 and 8 give 0 for text; the flags are the integer
  value of the argument, and 0, NULL, `'x'`, a BLOB and 16 are the flags error;
  `json_array_length` is 0 for an object and a scalar; `json` keeps `1.50e2`, `-0`,
  `1E400` and duplicate keys; wrong argument counts are prepare errors. The escape
  `\u0041` stays as written in rendered JSON text: the ADR's example for slice 6b came
  from the shell, which converts `\uXXXX` in its input, and is corrected.

- 2026-10-17: more native facts: the flags are `sqlite3_value_int64` of the argument
  (`'1e2'` is 1, `'2x'` 2, `'+3'` 3, `15.9` 15, `1e20` and `2^34+1` out of range), and the
  flags are checked before a NULL JSON argument; argument names resolve before the count
  check (`json_type(zz, 1, 2)` is `no such column: zz`).
- 2026-10-17: model. `Json/Validity.lean` (`standardJson`, a recognizer of canonical
  JSON; 2273 differential cases against `json_valid(X)` and `json_valid(X, 2)`, no
  mismatch), `Json/Functions.lean` (`json_type`, `json_array_length`, `json`) and
  `Json/Valid.lean` (`json_valid` and its flags); `JsonError.badFlags`, a described failure.
  `JsonFunction` gets four constructors; `Calls.lean` names the functions and checks the
  argument count after the arguments resolve (`jsonCall`, `wrongArgumentCount`).
  `Calls.lean` now imports `Resolution.Values`: `ValueIssue` was an automatic implicit
  there. Examples `Json/FunctionExamples.lean` and `Json/ValidityExamples.lean`. Authored
  cases `conformance/authored_json_functions.py` (18, all AGREE; 5 fail natively in the
  step phase and 2 in the prepare phase), mutants `conformance/json_function_mutants.py`
  (6), corpus writer `conformance/json_function_evidence.py` (corpus 23). The mutant
  "`json` re-rendering numbers" of the task is "`json` returning its argument as written":
  re-rendering numbers is already the mutant of slice 6b.

## Remaining

- Full checks, review, CI time, pull request A; then pull request B (claim corpus 23,
  `mustAgree`).
