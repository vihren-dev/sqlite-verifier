# Status: parser library, step 1 of ADR 0007

Created 2026-10-09. Status: IN PROGRESS (implementation done; macOS evidence open).
Task: [task](20261009-parser-library.task.md).
Specification: [ADR 0007](../docs/adr-0007-parser-library.md).

Relevant files: `parser/`, `build-support/default.nix`,
`build-support/parser-library.nix`, `tests/parser_test.py`, `justfile`,
`tools/ci_store_gc.py`.

## Findings

- A translation unit that includes `sqlite3.c` with `-DSQLITE_API=static
  -DSQLITE_EXTERN=` compiles with GCC 15 without warnings and defines no global
  symbol of its own (prototype, 2026-10-09).
- The retained corpora v1 to v5 have 11,080 distinct migration, setup, setup
  command and trace statement texts. With the 39 parser test inputs (the empty
  text is also a corpus text), the checks
  parse 11,118 distinct inputs. The recorded profiles have no compile option
  that is a grammar option.
- Grammar identities: 3.51.0
  `7c0495821ae35f29088747fd33c5bf52342b75dce5e896fec9d11bd74351b6d0`, 3.46.0
  `191f4283d9f99a43480717a72ed39c54b6242e2376269d6d4a29f8a17e74efea`. Both
  grammars have 409 productions and 186 tokens.
- Extracted grammar options: the 20 (3.51.0) and 19 (3.46.0) macros of the
  `parse.y` conditionals, and `SQLITE_ASCII`, `SQLITE_EBCDIC`,
  `SQLITE_OMIT_BLOB_LITERAL`, `SQLITE_OMIT_FLOATING_POINT`,
  `SQLITE_OMIT_HEX_INTEGER`, `SQLITE_OMIT_TCL_VARIABLE` from the tokenizer.
  `SQLITE_ASCII` and `SQLITE_EBCDIC` select the character set; SQLite defines
  `SQLITE_ASCII` itself, and `PRAGMA compile_options` reports neither.
- Lemon must be built without the library flags: a sanitized Lemon reports
  its own leaks and stops the build.
- Known limit of the identity: the character macros of `sqliteInt.h`
  (`sqlite3Isdigit` and others) and `SQLITE_DIGIT_SEPARATOR` are not part of
  it. They read the tables, which are. Including all of `sqliteInt.h` would
  give each patch release its own identity.

## Progress

- 2026-10-09: task and status files created in the jj workspace
  `parser-library`.
- 2026-10-09: library, dialect table, checks and CI wiring in one commit.
  `nix-build -A parserLibrary` in the sandbox: `load` parsed the RAISE case
  with both grammars in one process; `compare` found byte-identical output for
  all 11,118 inputs with both grammars; `sanitizer` found nothing. A planted
  leak (no `free` of the input copy) failed the sanitizer check with
  LeakSanitizer, 22,228 allocations. Changing the 3.46.0 identity in
  `parser/dialects.json` failed the Nix build of `parserLibrary.library` with
  "The sources of dialect 3.46.0 [] give grammar identity 191f…, but
  parser/dialects.json records 091f…". `just test-source`: 483 passed.
  `tests/test_ci_checks.py` lists the sandboxed `justfile` targets and now
  includes `parserLibrary`.
- 2026-10-09: review `20261009T093844Z-aa091822`: no must findings, three
  should findings (R1 table field literals, R1 prefix length literal, R10 release
  label message), all fixed in the following refactor commit.
- 2026-10-09: refactor commit `cdfdb8a9`, review `20261009T094022Z-cdfdb8a9`
  with no findings. Acceptance items 1, 2 and 4 of the ADR have evidence above;
  item 3 has Linux amd64 evidence only.
- 2026-10-09: rebased onto main after PR #56 merged. The only text conflict was
  `reviews/log.jsonl` (main's lines, then this branch's five). `parserLibrary`
  now receives `root` from `build-support/default.nix`, as the other imports
  do since PR #56. `just parser-library` passes; `just test-source` with
  `SQLITE_VERIFIER_RUNTIME_ROOT=build/runtime`: 483 passed. With the checkout
  as root, 36 tests on main fail because `just build` does not link
  `packages/belay-sqlite/.lake`; this branch does not change that.

- 2026-10-09: owner review of PR #71: move compiling and linking from Python
  into Nix with one derivation per grammar, and turn the check scripts into a
  pytest suite. Task file revised (outcomes 6 and 7).

## Measurements (Linux amd64, local, 2026-10-09)

| Step | Time |
| --- | --- |
| Library build, both grammars, `-O1` | 5.4 s |
| Library build with the sanitizers | 16 s |
| Sanitizer parse of 11,118 inputs with 2 grammars | 5.4 s |
| Comparison with the executables, both grammars | 12.9 s |
| Corpus text extraction | 12.5 s |
| All `parserLibrary` targets in the Nix sandbox, first build | 47 s |

## Remaining

- macOS arm64: the load test on a main or nightly CI run, or by the owner.
