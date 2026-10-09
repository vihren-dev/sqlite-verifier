# SQLite syntax boundary

The verifier and the conformance harness parse SQL with SQLite's own grammar and
tokenizer, compiled into one shared library that they load into their own
process: `lib/libsqlite-verifier-parser.so` (`.dylib` on macOS) in the runtime.
Nix builds it as `parserLibrary.library` in `build-support/default.nix`, and
`just build` links it at `lib/` in the checkout. Test inside the pinned
development shell: `just test-cases tests/parser_test.py`. No database is
opened and no SQL is executed, prepared, or schema-resolved.

`belay/sqlite/parser_library.py` loads the library with `ctypes`, only from the
runtime's explicit path, once for each process. It refuses a library with
another API version, or without a dialect for each profile in
`belay/sqlite/profiles.py`, and it holds its own lock for each call: the
library makes no promise for concurrent calls. `belay/sqlite/dialects.py`
selects the grammar of a profile from its release, its SQLite source id and the
grammar options among its compile options, and never falls back to another
dialect. `verify` uses the default dialect of its profile's release. The
conformance harness uses the dialect of each case's recorded profile; a case
without a built dialect is `MODEL_UNSUPPORTED` with the reason "no parser for
this dialect".

A parse runs in the verifier's process. It has no deadline and no crash
containment: the input and node limits bound it, and Lemon's LALR parsing is
linear in the number of tokens.

A successful parse document has status `PARSED`, never `VERIFIED`. It contains
the grammar identity as `grammar`, a root node index, and a flat node array.
Every node contains its upstream grammar symbol, `start`/`end` UTF-8 byte
offsets (end exclusive), and ordered child indexes. Terminals have no children.
Empty productions have zero-width spans. The implicit EOF semicolon also has a
zero-width span. Whitespace/comments are not nodes. The input root contains
ordered `cmdlist`/`ecmd` productions; trigger statements remain inside the
corresponding outer command. Symbols and offsets, together with original input
bytes, are sufficient for downstream semantic translation.

`INPUT_ERROR` indicates invalid UTF-8, embedded NUL, a lexical error, or rejection
by the grammar. `RESOURCE_LIMIT` indicates the 1 MiB input or 200,000-node bound
or allocation failure. Errors include a byte offset where available;
whole-text encoding/size errors use offset zero. The frontend maps
`RESOURCE_LIMIT` to `UNVERIFIED`: resource exhaustion is not evidence of
invalid SQL or a violated requirement.

## Grammar provenance and dialect

The build verifies hashes of the unmodified vendored sources, builds upstream
Lemon, and uses its `-E` preprocessing and `-g` grammar export. Expanded
productions, precedence, fallback identifiers, wildcard terminals, and the full
token inventory are retained. Explicit start symbol `input` compensates for
Lemon's action-dependent production export order. SQLite code-generation actions
are replaced by generic tree-building actions. There are no SQL-specific grammar
rules authored by this project. The build rejects token-inventory differences
between source grammar and amalgamation.

Tokenization calls the pinned `sqlite3GetToken` implementation and its contextual
`WINDOW`/`OVER`/`FILTER` helpers. Comments are enabled, matching the native default.
Numeric-separator adjacency validation follows upstream `sqlite3DequoteNumber`:
that lexical check occurs in SQLite's expression action rather than its tokenizer.
The built dialects are the default builds: no `SQLITE_OMIT_*` or
`SQLITE_ENABLE_UPDATE_DELETE_LIMIT` grammar switches are set.
This is default-build grammar recognition, not schema/name-resolution validity.
For example, an uninstalled virtual-table module or unknown table still parses.
Double-quoted tokens are recognized syntactically; the selected execution
profile governs subsequent expression resolution. Both profiles now use
library-default DQS. The translator rejects double-quoted expression fallback
as `UNSUPPORTED` while admitting supported quoted identifiers that resolve to
schema columns. The second grammar selects SQLite 3.46.0 syntax; it does not
select a migration framework.

The semantic translator must inspect all commands and existing-schema objects,
admit only its modeled forms, and report parsed unsupported forms as
`UNSUPPORTED`. Parse success alone establishes no applicability or safety claim.
Remaining trust includes upstream tokenizer/Lemon, generated tree actions, and
the downstream translator. Tests are conformance evidence, not a native parser
equivalence proof.

## Coverage

Each pinned default grammar has 409 productions, independently generated from
its release's sources. The regression suite exercises 20 scripts per release
across DDL, DML, CTEs, windows, triggers,
virtual tables, pragmas, transaction control, and EXPLAIN; malformed input,
encoding/resource boundaries, determinism, and byte spans are separate checks.
This script denominator is not production coverage or semantic completeness.
A separate RAISE-expression case distinguishes the grammars: support introduced
in 3.47 is accepted by 3.51 and rejected by 3.46, preventing version relabeling.
Public native fixture imports and formal/native comparisons are separate work.

Exact source/archive hashes and retained notices are recorded in
`parser/upstream/{README.md,sha256.json}` and
`parser/upstream-3.46.0/{README.md,sha256.json}`.

## Library build and dialect table

`parser/dialects.json` is the dialect table. It lists each release with its
source directory, and each built dialect (a release with the grammar options in
effect) with its grammar identity. A grammar identity is the SHA-256 digest of
Lemon's preprocessed `parse.y` for those options, the tokenizer and keyword code
of `sqlite3.c` (`tokenize.c` up to `sqlite3RunParser`), the character tables
`sqlite3UpperToLower` and `sqlite3CtypeMap`, and the options. The grammar
options of a release are the macros that the conditionals of `parse.y` and of
this tokenizer code test; the build extracts them. The build fails when the
sources give another identity than the table records. After a reviewed source
change, record the identity from the build's message. Only default dialects are
built: a dialect with grammar options fails the build.

The library contains one parser for each distinct identity, with its own
release's tokenizer. Each grammar's symbols have a unique prefix, SQLite's own
symbols stay internal, and the build fails unless the library exports exactly
the API of `parser/library.h`:

- `sqlite_verifier_parser_metadata` gives a JSON document with `api` (the API
  version, 1), `releases` (version, `sourceId`, `grammarOptions`), `dialects`
  (version, `grammarOptions`, `grammar`) and `grammars` (`grammar`,
  `productions`, `tokens`).
- `sqlite_verifier_parser_parse` takes a grammar identity and SQL bytes. It
  gives the parse document above. An unknown identity gives result code 1 and
  no document.
- `sqlite_verifier_parser_free` releases either document.

The library makes no promise for concurrent calls. The build checks that the
production count in the metadata equals Lemon's grammar export. Nix builds each
release and each grammar in its own derivation, so a patch release with an
unchanged grammar adds a release derivation and no parser.

The test suite `tests.parserLibrary` (`tests/parser_library_test.py`) loads all
grammars in one process and parses the RAISE case with each. It checks that the
library output equals the executable output for each release, for every parser
test input and every distinct SQL text of corpora v1 to v5. On Linux, it parses
the same inputs with a library built with AddressSanitizer, LeakSanitizer and
UndefinedBehaviorSanitizer.
