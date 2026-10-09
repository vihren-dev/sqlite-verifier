# Parser library, step 1 of ADR 0007

Created 2026-10-09. Status: DONE (2026-10-09).
Specification: [ADR 0007](../docs/adr-0007-parser-library.md), "Step 1: the
library" and "Acceptance evidence", items 1 to 4.

## Outcome

1. **One shared library contains a parser for each grammar.** A Nix attribute
   `parserLibrary` in `build-support/default.nix` builds a shared library with
   one parser for each distinct grammar identity of the built dialects. Today
   these are the default dialects of 3.51.0 and 3.46.0, so the library has two
   grammars. The `sqlite-parser` executables, their callers, the runtime
   packaging and the verifier are unchanged and do not use the library.
2. **The public API has a version number and three functions.** `metadata`
   returns a newly allocated JSON document with `api`, `releases`, `dialects`
   and `grammars`. `parse` takes a grammar identity, SQL bytes and their
   length, and returns a newly allocated JSON document and its length. An
   unknown grammar identity is a distinct result with no document. `free`
   releases a document. The library exports these three functions and no
   other symbol.
3. **The parse document keeps the executable format.** For each grammar and
   input, the library output equals the output of the executable of that
   release byte for byte, except that `"grammar":"IDENTITY"` replaces
   `"profile":"VERSION"`. The limits (1 MiB input, 200,000 nodes) and the
   statuses (`PARSED`, `INPUT_ERROR`, `RESOURCE_LIMIT`) are unchanged.
4. **The build extracts grammar options and checks the dialect table.** The
   build extracts the grammar options of each release from its sources. It
   computes the grammar identity of each dialect in a checked-in dialect
   table, and fails when an entry names another identity. The production count
   in the metadata equals the number of productions in Lemon's grammar export.
5. **A sanitizer job checks for memory faults and leaks.** On Linux amd64, the
   checks build the library with AddressSanitizer, LeakSanitizer and
   UndefinedBehaviorSanitizer and parse every parser test input and every
   distinct SQL text of every retained corpus with each grammar. A finding
   fails the check. The check does not depend on the model, the harness Python
   code or the documentation.
6. **Nix builds each grammar separately** (revised 2026-10-09, owner request
   after PR #56 merged). Nix reads `parser/dialects.json` when it evaluates the
   build, and makes one derivation for each release (its Lemon outputs and the
   identity check of its dialects), one for each distinct grammar identity (its
   generated parser and compiled objects), and one that links the library. A
   new release or grammar builds only its own derivations. Python does only
   the work that needs a program: the grammar transform, option extraction,
   identity and production checks, the metadata and the export check.
7. **The checks are a pytest suite** (revised 2026-10-09). The load test, the
   comparison and the sanitizer job are tests in the `parserLibrary` suite of
   `build-support/tests.nix`, so `just test-full` and CI run them like the
   other suites, with per-test timeouts and JUnit reports.

## Tests

- Unit tests of the build code with small synthetic sources: grammar option
  extraction from Lemon conditionals and from the tokenizer sources; the
  identity changes when the grammar, the tokenizer, the character tables or
  the options change, and does not change for another source directory name;
  a dialect-table entry with another identity, an unknown release, a release
  label that differs from `sqlite3.h`, or grammar options that the release
  does not have fails the check; the metadata document has the documented
  fields; the corpus text extraction reads both corpus formats.
- **Load test** (pytest suite `parserLibrary`, Linux amd64 and macOS arm64): one process loads the
  library, reads the metadata, checks `api` and the export list, and parses
  the `RAISE` case with each grammar: 3.51.0 accepts it and 3.46.0 rejects it.
  An unknown grammar identity gives the distinct error with no document.
- **Comparison** (pytest suite `parserLibrary`): for each grammar, the library output equals the
  executable output for all parser test inputs and all distinct SQL texts of
  every retained corpus, except for the `grammar` field.
- **Sanitizer job** (pytest suite `parserLibrary`, Linux amd64): the same inputs with each grammar, on
  the sanitized library, with leak detection.
- **Build check evidence** (status file): a changed dialect-table entry fails
  the Nix build, with the message.

## Relevant source and constraints

- `parser/main.c`, `parser/tokenizer.c`, `parser/runtime.h` and
  `parser/generate.py` build the executables in the `parsers` attribute of
  `build-support/default.nix`. Step 1 keeps the executables as they are; the
  comparison needs them unchanged. Step 2 moves the parse and output code
  into the library and deletes the executables.
- PR #56 has merged, so the step 1 limit on existing build files no longer
  applies. `tests/nix_suites.json` must equal the suites of `tests.nix`, and
  `tests/test_nix_test_targets.py` lists the suites and the inputs that
  invalidate them.
- Per-grammar caching needs per-release inputs: a release derivation must not
  read the whole dialect table, or a new release would rebuild every grammar.
- `sqlite3GetToken` reads past the token until a NUL byte. The executable
  reads the file into a zeroed buffer. The library must copy the caller's
  bytes into a buffer with a NUL terminator.
- Two tokenizers in one library: each grammar is one translation unit that
  includes `sqlite3.c` with `SQLITE_API` and `SQLITE_EXTERN` defined so that
  all SQLite symbols are internal. The tokenizer and Lemon functions of a
  grammar get a unique prefix. The library is built with hidden visibility,
  and only the API functions are exported.
- Grammar identity inputs. The generated grammar file is Lemon's `-E` output
  for the options in effect; it has no path names, so a release in another
  directory with the same `parse.y` has the same identity. The tokenizer and
  keyword sources are the `tokenize.c` section of the amalgamation up to
  `sqlite3RunParser` (it includes `keywordhash.h`), and the character tables
  `sqlite3UpperToLower` and `sqlite3CtypeMap` from the `global.c` section,
  which the tokenizer reads. The rest of `tokenize.c` (`sqlite3RunParser`,
  `sqlite3Normalize`) is not compiled into the parser, and its conditionals
  (`SQLITE_DEBUG`, `YYTRACKMAXSTACKDEPTH`) do not change syntax. Character
  macros in `sqliteInt.h` are not part of the identity; a release that changes
  them without changing the tables is a known limit, recorded in the status.
- Grammar options are the macros that Lemon's `%ifdef`, `%ifndef` and `%if`
  test in `parse.y`, and that C conditionals test in the tokenizer sources.
  Keyword omissions are decided in `mkkeywordhash.c`, which is not vendored;
  the ADR leaves non-default dialects open, so the build refuses a dialect
  with grammar options.
- Corpus texts: the migration, setup, setup command and trace statement texts
  of corpora v1 to v5 (11,080 distinct texts on 2026-10-09). The extraction
  reads the corpus files directly, so the sanitizer job does not depend on the
  conformance harness code.
- macOS arm64: this environment has only Linux amd64. The load test is
  portable; its macOS run is evidence that the owner or a main or nightly CI
  run records.
