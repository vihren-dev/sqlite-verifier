# ADR 0007: SQLite parser as one in-process library for all grammars

Date: 2026-10-07. Revised: 2026-10-08. Status: PROPOSED.
Audience: designers and reviewers.
Related: [SQLite syntax boundary](sqlite-parser.md),
[trust boundary](trust-boundary.md),
[ADR 0005](adr-0005-conformance-corpus-scale.md),
[ADR 0006](adr-0006-model-boundary-and-execution-levels.md).

The 2026-10-08 revision describes the code layout after
[PR #56](https://github.com/vihren-dev/sqlite-verifier/pull/56), which implements
ADR 0006, and divides the development into two steps.

## Context

The verifier reads SQL through SQLite's own grammar and tokenizer. The build
generates a Lemon parser from each pinned release's `parse.y`, replaces the
code-generation actions with tree-building actions, and links it with that
release's `sqlite3GetToken`. The result is one executable per release:
`build/sqlite-parser` (3.51.0) and `build/sqlite-parser-3.46.0`.

This ADR uses the file layout after PR #56. That PR moves the SQL frontend from
`migration_check/` into the `belay.sqlite` package, as ADR 0006 decides. File
names in `belay/sqlite/` are therefore given as text, not as links.

`parse` in `belay/sqlite/sql_tree.py` calls the executable once for each SQL
text. Each call writes the text to a new temporary file, starts a process with
a 5-second deadline, and reads a JSON syntax tree from its output. The caller
supplies the executable path: in the verifier,
[`Runtime.locate`](../migration_check/runtime.py) maps a version to an
executable name; in the conformance harness, the path comes from the
conformance runtime root.

This cost is small for `verify`, which parses a few texts. It is large for
conformance replay, which parses thousands. Measured on macOS arm64:

| Measurement | Executable | In-process prototype |
| --- | --- | --- |
| One call to the parser, mean over 9,399 distinct SQL texts | 3.53 ms | 0.135 ms |
| `sql_tree.parse` for all 4,376 migrations of corpus v5 | 18.0 s | 1.8 s |

Starting any process costs about 2.5 ms on the same machine. The parse itself
takes microseconds for a typical migration of 58 bytes. The prototype included
the unchanged `parser/main.c` and wrote its JSON to memory. Its output was
byte-identical to the 3.51.0 executable for all 9,399 texts: every distinct
migration, setup and statement text in corpus v5, an embedded NUL, invalid
UTF-8, an input over 1 MiB, and deep nesting.

The project expects to support many SQLite releases. Most releases since 3.35
are candidates, and their patch releases add more. One executable for each
release does not scale. One shared library for each release does not scale
either: each one contains a full `sqlite3.c` with the same exported symbols.

## Decision

### One library, no executable

The SQLite parser is a shared library that the verifier loads into its own
process. The `sqlite-parser` executables are removed, with their callers and
tests. No command-line parser remains as a fallback.

A separate parser process is not part of this decision. It can be added later
as a wrapper over the library. The triggers for that work are listed under
"When to revisit".

### All supported grammars in the same library

The grammar of a SQLite build depends on its release and on some of its
compile options. `parse.y` adds or removes rules with `%ifdef` and `%ifndef`,
for example for `SQLITE_ENABLE_UPDATE_DELETE_LIMIT` or `SQLITE_OMIT_TRIGGER`.
Some `SQLITE_OMIT_*` options also remove keywords from the tokenizer. Most
compile options, such as `SQLITE_MAX_COLUMN` or `SQLITE_THREADSAFE`, have no
effect on syntax.

- The **grammar options** of a release are the macros that its `parse.y` and
  its tokenizer and keyword sources test. The build extracts them from the
  sources. Nobody maintains this list by hand.
- A **dialect** is a release together with the subset of its grammar options
  that is in effect. The default build of a release is the dialect with no
  grammar options.
- A **grammar identity** is the SHA-256 digest of the inputs that decide syntax
  and tokens for a dialect: the generated grammar file, the tokenizer and
  keyword sources, and the grammar options in effect.
- A **dialect table** maps each built dialect to its grammar identity. The
  build computes each identity from the sources. It fails when an entry names
  an identity that its sources do not produce. Two dialects share a parser
  only when their identities are equal.
- Each grammar's generated symbols have a unique prefix. Each tokenizer is
  compiled in its own translation unit, with SQLite's symbols internal to that
  unit. The library exports only its public API.

The library contains one parser for each distinct grammar identity of the built
dialects. Today it builds two dialects, the default builds of 3.51.0 and
3.46.0. Their grammars differ, for example in `RAISE` expressions.

For example, if the patch releases 3.51.1 and 3.51.2 do not change `parse.y`,
the tokenizer or the keywords, their default dialects have the same identity as
3.51.0. Adding them adds two table entries and no parser. A release that adds
only SQL functions also keeps its grammar: a function call is a name with
arguments.

The identity is a digest of source text. A comment edit in `parse.y` therefore
gives a new identity, although the parser accepts the same input. This costs
one more parser. It never makes two different grammars share one.

### Public API

The C API has a version number and three functions:

- `metadata`: output is a newly allocated JSON document that describes the
  library.
- `parse`: input is a grammar identity, the SQL bytes and their length. Output
  is a newly allocated JSON document and its length. An unknown grammar
  identity is a distinct error, with no document.
- `free`: releases a document from `metadata` or `parse`.

The metadata document contains:

| Field | Content |
| --- | --- |
| `api` | The API version. |
| `releases` | For each release: the version, the SQLite source id, and its grammar options. |
| `dialects` | For each built dialect: the version, the grammar options in effect, and the grammar identity. |
| `grammars` | For each grammar identity: the number of productions and tokens. |

The parse document keeps today's format, except that `grammar`, the grammar
identity used, replaces `profile`. A grammar can serve several releases, so
the parse result does not name one release. The limits stay: 1 MiB of input
and 200,000 nodes give `RESOURCE_LIMIT`. Invalid UTF-8, NUL and syntax errors
give `INPUT_ERROR`.

The library makes no promise for concurrent calls. Callers parse one text at
a time. `ctypes` releases Python's global interpreter lock during a foreign
call, so the binding holds its own lock for each call.

### Python binding

The binding is part of the `belay.sqlite` frontend, because ADR 0006 gives the
frontend the ownership of the pinned parser invocation. Like the current
`parse`, it takes an explicit library path from its caller and does no runtime
discovery. In the verifier, `Runtime.locate` in `migration_check/runtime.py`
returns the path of the installed library instead of an executable path. The
conformance harness takes the path from its runtime root.

The binding uses `ctypes` from the standard library, so it adds no dependency.
It loads the library once per process, only from the explicit runtime path. It
never searches the library path of the environment. It reads the metadata once
when it loads the library, and refuses a library with a different `api`.

The binding passes the caller's `bytes` directly. Python `bytes` cannot change,
so the temporary-file snapshot is no longer necessary. The existing checks of
the JSON nodes in `sql_tree.parse` stay unchanged. The binding also checks that
`grammar` equals the requested grammar identity.

A helper selects the grammar identity for a profile:

1. It finds the profile's release in `releases`.
2. It checks that the profile's SQLite source id equals the source id of that
   release. A profile with a wrong version label then cannot select a grammar
   from other sources.
3. It takes the profile's compile options, as `PRAGMA compile_options` reports
   them, and keeps those that are grammar options of the release.
4. It finds the dialect for the release and these options in `dialects`.

Each failed step is a rejection that names the release, the options and the
dialects that the runtime has. The helper never falls back to another dialect.
Callers that already know a grammar identity call `parse` directly.

`%ifdef` tests only whether a macro is defined. Step 3 therefore compares
option names without values. If a later `parse.y` tests a macro value, the
grammar options of that release include the value, and step 3 compares it.

Profiles of `verify` contain only a release version today. Until profiles
record compile options, `verify` uses the default dialect of its release.

### Supported profiles stay a product decision

The metadata tells which dialects the parser can read. It does not tell which
profiles the verifier supports: that also needs model semantics and
conformance evidence. The supported profiles therefore stay an explicit list
in the Python code, in `belay/sqlite/profiles.py`. When it loads the library, the binding checks that each
supported profile resolves to a built dialect, and fails if one does not. A
dialect in the library never adds a supported profile by itself. For example,
the library can contain a dialect only to record conformance evidence before
the model supports it.

## Consequences

- **No parser deadline.** A call into the library cannot be stopped. The result
  "SQL parser exceeded its time limit" is removed. The input and node limits
  stay, and Lemon's LALR parsing is linear in the number of tokens. Lean
  processes keep their deadlines.
- **No crash containment.** A fault in the parser stops the verifier or the
  test run. Before, it failed one parse.
- **Memory faults can corrupt verifier state.** In-process memory faults are
  not always visible as crashes, and they can change data without a change in
  output. The sanitizer job in "How the parser library is tested" checks for
  them.
- **Trust boundary.** The parser was already trusted code. The
  [trust boundary](trust-boundary.md) must say that it now runs inside the
  verifier process, without a deadline.
- **Packaging.** The runtime and the release archive contain the library
  instead of the executables. The installer tests must still show that no
  ambient tool or library is used.
- **Documentation.** [SQLite syntax boundary](sqlite-parser.md) describes the
  library, the API, the metadata and the dialect table.

## How the parser library is tested

Each claim about the parser has its own evidence:

| Claim | Evidence |
| --- | --- |
| The parser reads the syntax of SQLite, for each dialect | Construction from hash-checked upstream sources, and the conformance pipeline |
| The syntax trees are correct | The conformance pipeline, and the parser tests |
| No memory faults or leaks | The sanitizer job |
| All grammars work in one process | The load test |
| The build and the metadata are correct | The build checks |
| The library gives the same result as the executables | A one-time comparison in step 1 |

**Construction.** The build checks the hashes of the unmodified upstream
sources. It keeps every production, precedence rule and token of the upstream
grammar, and replaces only the actions. It fails when the token inventories of
the grammar and the tokenizer differ. These checks exist today and stay.

**Conformance pipeline.** This is the main evidence that the parser agrees
with SQLite. Each corpus case is parsed with the dialect of its profile, then
mapped, resolved and executed in the model, and compared with native SQLite.

- A parser rejection of a statement that native SQLite ran is a harness error,
  and a harness error fails the tests.
- A wrong syntax tree changes the model result, for example through operator
  precedence, so the case disagrees.
- A parser acceptance of a statement that SQLite rejects also gives a
  disagreement when the statement is in the admitted scope. Outside that scope,
  the mapping refuses the statement as `UNSUPPORTED`, and `UNSUPPORTED` never
  becomes `VERIFIED`.
- The harness parses every case before it checks the profile. Today the
  harness rejects the cases of corpus v5 for their profile before it parses
  them, so they give no parser evidence. With this change, every distinct SQL
  text of every retained corpus goes through the parser.

**Parser tests.** The existing parser tests call the library through the
binding. They take the grammars and dialects from the metadata, so a new
grammar is tested without a test change. They cover valid and invalid scripts,
the resource limits, exact byte spans, and the `RAISE` case that each release
parses differently.

**Sanitizer job.** A CI job builds the library with AddressSanitizer,
LeakSanitizer and UndefinedBehaviorSanitizer. It parses every parser test input
and every distinct SQL text of every retained corpus, with each grammar. A
finding fails the job. The executables freed all memory when they exited, but
the library runs in a long process, so a leak also fails the job.

**Load test.** One process loads all grammars on Linux amd64 and macOS arm64,
and each grammar gives its own result for the `RAISE` case.

**Build checks.** The build extracts the grammar options of each release and
checks each dialect-table entry against the identity that its sources give. The
production count in the metadata is checked against Lemon's own export of the
grammar.

**One-time comparison.** In step 1, for each grammar, the library output must
equal the executable output byte for byte, except that `grammar` replaces
`profile`. The inputs are all parser test inputs and all distinct SQL texts of
every retained corpus. The comparison ends when step 2 removes the executables.

**Not tested on purpose.**

- Stored expected syntax trees, a separate syntax comparison with SQLite, and a
  measure of production coverage. The conformance pipeline already checks the
  behavior that these would check. Syntax outside the admitted scope is
  refused, so its coverage does not affect a result.
- Fuzzing. SQLite's own grammar and tokenizer are fuzzed upstream. A sanitizer
  finding or a parser crash is a trigger in "When to revisit".
- Concurrent calls. The library makes no promise for them.

## Development in two steps

PR #56 moves and changes the files that the binding and the callers use:
`belay/sqlite/sql_tree.py`, `belay/sqlite/profiles.py`,
`migration_check/runtime.py` and the runtime packaging in `build-support/`.
That PR is frozen during its owner review. The work is therefore divided into
two steps, each with its own task, status record and pull request. The
executables stay available until the end of step 2.

**Step 1: the library.** It can start when this ADR is accepted, before PR #56
merges. It adds the shared library, its public API and metadata, the
extraction of grammar options, the dialect table check, the sanitizer job, and
a comparison of the library with the executables. It changes `parser/` and
adds new build definitions. Its only change to an existing build file is the
new library attribute in `build-support/default.nix`. It changes no caller,
no runtime discovery and no packaging, and the verifier does not use the
library yet.

**Step 2: the switch.** It starts after PR #56 merges. It adds the binding in
`belay.sqlite` and the profile resolution helper, changes `parse`, the verifier
runtime and the conformance harness to use the library, makes the harness
parse every case before it checks the profile, and removes the executables,
their callers and their tests. It updates the runtime packaging,
the installer tests, the [SQLite syntax boundary](sqlite-parser.md) and the
[trust boundary](trust-boundary.md).

## Acceptance evidence

Step 1, before step 2 starts:

1. For each grammar, the library output equals the executable output, byte for
   byte, except that `grammar` replaces `profile`. The inputs are all parser
   test inputs and all distinct SQL texts of every retained corpus.
2. The sanitizer job, with LeakSanitizer, passes on the same inputs.
3. Both grammars load in one process on Linux amd64 and macOS arm64.
4. The build extracts the grammar options of each release, and a changed
   dialect-table entry fails the build.

Step 2, before the executables are removed:

5. Profile resolution gives the expected dialect for the current profiles. It
   rejects an unknown release, a different source id, and grammar options
   without a built dialect. It ignores compile options that are not grammar
   options.
6. Each supported profile resolves to a built dialect when the library loads.
7. The conformance pipeline parses every case of every retained corpus,
   including cases that it rejects later for their profile. No statement that
   native SQLite ran is rejected by the parser.
8. The installer tests pass with the library.
9. The time of `parse` over the corpus v5 migrations is measured and
   recorded, before and after.

## Alternatives considered

**Keep one executable for each release.** Rejected. Process start-up dominates
the cost, and the number of executables grows with each release.

**A persistent parser process that reads many requests.** Not chosen now. It
keeps the deadline and the crash containment, and removes most of the start-up
cost. It adds a request protocol and process management. It can be built over
the library when needed.

**One shared library for each release.** Rejected. Each library contains the
same SQLite symbols. Loading many of them into one process depends on
platform-specific symbol resolution.

## When to revisit

Add a process wrapper over the library when one of these occurs:

- a sanitizer finding or a crash in the parser;
- a parse that takes longer than the old 5-second deadline;
- a need to parse SQL from untrusted sources in a shared service.

Add a promise for concurrent calls, with its own tests, when a caller needs to
parse in parallel.

## Not decided here

- **Building non-default dialects.** The build makes only default dialects
  today. A dialect with grammar options needs Lemon to run with those options
  defined. When an option changes keywords, it also needs a keyword table
  generated from SQLite's canonical sources, which are not vendored. The first
  profile with grammar options decides how to build it.
- **Fetching upstream sources.** Each release vendors about 10 MB of SQLite
  sources under `parser/`. With many releases, the build should fetch them by
  fixed hash instead. That changes how sources are reviewed, and needs its own
  decision.
- **Profiles in the Lean model.** `ExecutionProfile` is an enumeration with one
  constructor for each release. Support for many releases needs a structure
  with capability fields. That is a model decision.
