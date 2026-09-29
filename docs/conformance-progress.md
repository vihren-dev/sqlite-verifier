# Frozen progress and measured coverage (W7)

Use `just conformance-progress` to replay **corpus v2: 183 cases** through today's
frontend and compiled classifier. Its baseline is 8 AGREE, 175 MODEL_UNSUPPORTED,
0 DISAGREE and 0 HARNESS_ERROR. The [report](../reports/20260929-adr4-corpus-v2-progress.json)
contains per-case, test-area and requirement-ID counts. V2 contains v1's exact 177
records plus six authored cases; its increase in agreements is **corpus growth**,
not model progress. V1 remains immutable. Comparisons across model revisions use
the same corpus version and content digest. Tests require all prior agreements
and reject disagreements and harness errors.

The six authored cases cover BLOB affinity, explicit rollback, nested BEGIN,
unique-index duplicates, distinct NULL index entries, and ADD on populated rows.
Their nine requirement tags identify specific scenarios, not exhaustive satisfaction
of those requirements. Untagged upstream cases receive no credit merely because
their source file cites a requirement elsewhere.

## Regenerated requirements

`just conformance-requirements` rebuilds marked HTML and its database using the
release's own `wrap.tcl`, `matrix.tcl`, and public source/test evidence scanner.
The vendored archive is the user-supplied `version-3.51.0` documentation source,
revision `93f1a4577785f72b4183843a7c8d33285bc36bce6f6b5258f428a6c844a0099c`.
Original tar SHA256: `f3a39333897823546bca5924899bafaf7f593571863666221e5a38246f065423`.
The archive is retained because automated downloads encountered access gates.

The [inventory](../conformance/requirements-3.51.0.json) contains 3,500 extracted
text requirements, with full IDs and normalized text. Tests independently hash
every ID. The working matrix has 164 rows: the four selected areas below plus
the referenced omitted-default requirement. Zero-test rows remain visible.

| Release documentation area | Requirements | Public Tcl evidence IDs |
| --- | ---: | ---: |
| datatype3 | 99 | 0 |
| lang_transaction | 26 | 0 |
| lang_createindex | 17 | 0 |
| lang_altertable | 21 | 9 |

These are the regenerated 3.51.0 counts, not the live-site counts quoted in the
historical research report. Public Tcl evidence references do not mean those
tests were imported into our corpus.

## Measured execution coverage

Run `just conformance-coverage /path/to/llvm-cov build/fresh-coverage-directory`.
On macOS, `xcrun --find llvm-cov` locates the tool. The command records its version;
Nix supplies separately instrumented model and Clang SQLite builds. Existing
counter directories are rejected to prevent accumulation across measurements.

The [measurement](../reports/20260929-adr4-coverage.json) uses 93 admitted cases:
80 fixed-seed generated, five original curated, and eight admitted frozen cases.
The other 175 frozen cases are explicitly excluded as model-unsupported.
Instrumented model verdicts/positions must equal the normal runner's; instrumented
native traces must equal the recorded traces. The report binds source and case
digests and lists every instrumented arm and reached native function.

- Model: 7/7 statement constructors, 7/8 error constructors, and 36/41 explicit
  match arms in `step`, `SqlState.finish`, `literalStep`, `statementReady`,
  `advance`, `runSqlFrom`, and `supportedSqlFrom`. `invalidDefinition` is an
  admission boundary, absent from this admitted workload. Uncovered arms remain
  listed; helper functions and Boolean branches are outside this measurement.
- Native: 6,003/16,272 gcov branch arcs within reached functions. This includes
  initialization and observation SQL as well as migrations, under a separate
  `-O0` instrumented library. It is not whole-SQLite coverage. Unreached functions
  are counted separately and excluded from this branch denominator.

Coverage is a work list, not proof of refinement. These instrumented executables
are neither shipped artifacts nor tier-two/four proof tools. Ordinary kernel and
axiom tests use the uninstrumented library. Linux execution remains for native CI;
the recorded live measurements were taken on aarch64-darwin.
