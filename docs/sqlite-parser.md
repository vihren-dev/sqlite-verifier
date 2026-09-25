# SQLite syntax boundary

Build: `python3 parser/build.py`. Test: `python3 tests/parser_test.py`.
The executables `build/sqlite-parser INPUT.sql` (3.51.0) and
`build/sqlite-parser-3.46.0 INPUT.sql` each read one UTF-8 file and emit JSON.
No database is opened and no SQL is executed, prepared, or schema-resolved.

Successful output is `PARSED`, never `VERIFIED`. It contains the actual upstream
header's version as `profile` (`3.51.0` or `3.46.0`),
a root node index, and a flat node array. Every node contains its upstream grammar
symbol, `start`/`end` UTF-8 byte offsets (end exclusive), and ordered child indexes.
Terminals have no children. Empty productions have zero-width spans. The implicit
EOF semicolon also has a zero-width span. Whitespace/comments are not nodes.
The input root contains ordered `cmdlist`/`ecmd` productions; trigger statements
remain inside the corresponding outer command. Symbols and offsets, together
with original input bytes, are sufficient for downstream semantic translation.

`INPUT_ERROR` indicates invalid UTF-8, embedded NUL, a lexical error, or rejection
by the pinned grammar. `RESOURCE_LIMIT` indicates the 1 MiB input or 200,000-node
bound or allocation/stack failure. Errors include a byte offset where available;
whole-file encoding/size errors use offset zero. Error output is bounded. These
parser-internal statuses must be mapped by the verifier: resource exhaustion is
not evidence of invalid SQL or a violated requirement. Usage/I/O errors exit
nonzero with stderr diagnostics. Any accepted parse exits zero.

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
No `SQLITE_OMIT_*` or `SQLITE_ENABLE_UPDATE_DELETE_LIMIT` grammar switches are set.
This is default-build grammar recognition, not schema/name-resolution validity.
For example, an uninstalled virtual-table module or unknown table still parses.
Double-quoted tokens are recognized syntactically; the selected execution
profile governs subsequent expression resolution. The existing 3.51.0 profile's
DQS=0 rule must not be bypassed by the semantic translator. The second grammar selects SQLite 3.46.0 syntax; it does not select a migration framework.

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
