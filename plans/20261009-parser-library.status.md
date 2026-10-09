# Status: parser library, step 1 of ADR 0007

Created 2026-10-09. Status: IN PROGRESS.
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
  command and trace statement texts. The recorded profiles have no compile
  option that is a grammar option.

## Progress

- 2026-10-09: task and status files created in the jj workspace
  `parser-library`.

## Remaining

- Everything in the task file.
