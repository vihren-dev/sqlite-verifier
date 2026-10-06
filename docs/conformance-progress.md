# Frozen progress and measured coverage (W7)

Current state, 2026-10-06: [v5](../conformance/corpus-v5/manifest.json) contains
4,376 cases in 109 shards: 4,307 upstream cases and 69 authored cases.
The [yield report](../reports/20261002-adr5-review-yield.json) accounts for all
171 sources, every zero-yield source and all 57 expression cohorts.
Labels describe scenarios or source-file membership, never feature executions.

[macOS full native replay](../reports/20261002-adr5-review-v5-native-darwin.json)
passes all cases. [Current progress](../reports/20261002-adr5-review-v5-progress-darwin.json)
records 4,376 MODEL_UNSUPPORTED, no disagreements or harness errors, and 129
represented rows out of all 3,500 requirements. Model semantics are unchanged.

Current v5 uses 184 development cases. Retained direct measurements pass on
[macOS](../reports/20261002-adr5-review-v5-sample-darwin.json) in 37.21 seconds and
[Linux](../reports/20261002-adr5-review-v5-sample-linux.json) in 56.58 seconds,
with identical selected identities and the unchanged 60-second phase bound.
Hosted [CI validation](../plans/20261006-adr5-hosted-validation.md) passes on
ubuntu-22.04 and macos-14, including the v5 sample and full model/upstream checks.

[Linux full native replay](../reports/20261002-adr5-review-v5-native-linux.json)
passes all 4,376 cases in 98.13 seconds using file-backed databases on tmpfs.
The [retained execution record](../reports/20261005-adr5-review-execution/README.md)
predates workload-gate closure and preserves ext4 timeouts and diagnostics.
[Linux full progress](../reports/20261002-adr5-review-v5-progress-linux.json)
matches macOS case results and requirement views. The
[core gate](../reports/20261005-adr5-review-gates.json) and the external workload
suite in its owning repository are complete; model extension is subsequent work.
V5 uses 8,694,264 bytes; v1–v5 use 12,235,391 bytes, within both budgets.
Frozen v1–v4 remain unchanged. `just test-full`, CI and packaging retain
full checks; explicit historical replay remains supported.

## Full native replay storage

Run `just conformance-corpus /path/to/native-storage` with an existing writable
directory and at least 10 GiB free, as required by the development resource
policy. The directory is an explicit input; the command never substitutes
ambient temporary storage. The report in `build/corpus-progress.json` records
the selected device and capacity, every actual `case.db` path, native timing,
the command and unchanged code, corpus, runtime and native-library hashes.
Fixture directories are removed when each case finishes.
The report output must be outside the selected corpus.

On Linux, the retained ext4 full-run attempts exceeded both 420 and 900 seconds.
The paired records are identical on ext4 and tmpfs; the long trigger setup took
10.72 seconds on ext4 and 0.10 seconds on tmpfs. The full replay completed on
tmpfs within the existing 420-second bound. Select tmpfs explicitly for that
Linux full-run condition. For example, first inspect its mount and capacity
with `findmnt -T /dev/shm` and `df -B1 /dev/shm`, create a private directory
under that mount, then pass that directory to `just conformance-corpus`.
SQLite still uses ordinary files and its unchanged profiles and PRAGMAs. These
measurements do not establish ext4 full-run performance or crash durability.

To replay another frozen version, supply the same explicit storage input:

```sh
timeout 420 python3 -m conformance.corpus conformance/corpus-v5 \
  --runtime-root build/conformance --native-check \
  --temporary-root /path/to/native-storage --output build/corpus-progress.json
```

`just conformance-progress` classifies frozen observations with the current
frontend and model. It does not run fresh native comparisons and needs no
native storage argument. Small native recordings and samples retain the
ambient-storage library primitive; callers can pass `temporary_root` and a
`fixture_paths` list to `native_replay` or `record_sql` to audit explicit storage.

## Historical v4 and v3 baselines

The [v4 artifact](../conformance/corpus-v4/manifest.json) freezes 1,264 generic
cases in 27 source/part shards. All observations pass fresh native replay. Its
[full report](../reports/20261002-adr5-c6-v4-progress.json) keeps all 3,500
requirement rows, with 110 represented, and reports 1,264 MODEL_UNSUPPORTED.
The model cannot yet consume the expanded profiles.

The historical progress command used all v4 cases. Its
[C7 baseline](../reports/20261002-adr5-c7-v4-progress.json) adds verdicts and
denominators for four parts, 80 overlapping labels and 27 ordered shards,
while retaining every requirement row and per-case result. This historical
report's combined `byFeature` counts include source-file membership, not
executions of each named feature. Manifest, profiles, evidence, shard
bytes, frontend/harness and both compiled runtime files are bound by identity.

New reports separate `byCaseFeatureLabel` (authored or workload scenario
annotations), `bySourceFileLabel` (membership in a labelled upstream file),
and `byUnscopedFeatureLabel` (historical annotations whose scope is unknown).
Labels count once per case within their scope and may overlap. A case from
`json101.test` labelled `json_each` contributes only to source-file membership;
it does not establish that its SQL executes `json_each`. No label view measures
SQL execution coverage. Historical manifests and reports retain their original
`byFeature` bytes; replaying them today produces the separated label views.

The historical development tier used 100 cases: all 66 authored
cases, both synthetic cases, and one lowest identity hash per nonempty upstream
source shard plus eight additional lowest hashes. Selection ignores native
acceptance and model verdicts. The [Darwin measurement](../reports/20261002-adr5-c7-sample-darwin.json)
records fresh loading, native replay and model classification in 6.27 seconds;
the [Linux measurement](../reports/20261002-adr5-c7-sample-linux.json) records
19.70 seconds with identical profiles and selected input identities.
All 100 cases remain unsupported. The phase has a 60-second deadline.
`just test-full`, CI and packaging retain the full model suite. Historical
corpora and reports remain readable without changing their membership.

ADR 0004's historical progress command replayed **corpus v3: 370 cases** through its
frontend and compiled classifier. The [review report](../reports/20260929-adr4-corpus-v3-progress.json)
records 11 AGREE, 359 MODEL_UNSUPPORTED, no disagreements and no harness errors.
V3 preserves v2's 183 records exactly and adds 164 upstream and 23 authored cases.
These added agreements are corpus growth, not model progress. V1 and v2 remain
immutable; compare model revisions using the same corpus version and digest.

ADR 0005's C6 tools record profiled outputs and validate the v4 freeze.
The [synthetic workload](conformance-workload.md) exercises the
external-directory commands; it does not complete the actual workload gate.

The raw verdict remains unchanged when a case contains queries. A separate
`queryDiagnostic` examines successful trailing SELECTs and metadata PRAGMAs,
requires unchanged native state, and submits the remaining prefix to Lean:

- `BLOCKED_ONLY_BY_QUERIES`: a nonempty migration prefix agrees (currently zero).
- `QUERY_ONLY_CASE`: the agreeing prefix is empty (42 cases).
- `PREFIX_MODEL_UNSUPPORTED`: removing trailing observations still leaves an
  unsupported prefix (50 cases).
- `OTHER_UNSUPPORTED`: no qualifying trailing observation projection (267 cases).

Original SQL, query result rows and traces remain frozen. Queries between writes,
setting PRAGMAs and failed queries are not removed. No query-only case counts as
DDL progress. Frontend syntax rejection matching a native SQL error remains an
unsupported input with `frontendStatus: INPUT_ERROR`; parser transport failures
and inconsistent statement boundaries are harness errors.

## Requirement evidence

The current matrix keeps **all 3,500 release requirement rows**, including rows
with zero cases. Each case counts once per row even if it carries both a short
and a full requirement ID. Nearest, unambiguous upstream `EVIDENCE-OF` comment
blocks carry source lines and file digests; ambiguous or obsolete references
remain provenance without credit. These are scenario counts, not proof of entire
requirements.

Requirement rows count explicitly attributed scenarios. They and authored
feature annotations describe the cases, rather than proving every behavior of
a requirement or measuring executions of SQL syntax or functions.

The [C5 authored report](../reports/20261001-adr5-c5-authored.md) records **60 to
98 rows with cases**, with 38 newly represented rows and no lost rows. It replaces
the evidence for 29 legacy authored scenarios and adds 14 neutral scenarios.
All 43 records have typed outputs and explicit profiles and pass fresh native
replay. Their current model verdict is `MODEL_UNSUPPORTED`; this is evidence
growth, not added SQL support. C6 determines the final corpus membership.

The historical v3 report had **60 of 182 rows with cases**, up from 9 of 164 in
v2. Its denominator included four selected documentation areas and additional
requirements referenced by the expanded corpus. That growing denominator is
replaced by the complete release inventory in new reports.

Authored additions cover numeric/text/REAL conversions, declared-type precedence,
transaction commit/rollback and savepoints, CREATE INDEX, uniqueness failures,
IF NOT EXISTS, DROP INDEX, collation, descending indexes and prohibited subqueries.
Unsupported cases intentionally remain useful future-model evidence.
The new neutral cases also cover triggers, cascades, constraint rollback,
UPSERT/RETURNING, aggregates, joins, casts, REAL arithmetic, query windows,
controlled time and JSON. JSON has feature metadata because this requirement
inventory has no `json_extract` or `json_each` row.

`just conformance-requirements` uses SQLite's own `wrap.tcl`, `matrix.tcl` and
public evidence scanner. The [inventory](../conformance/requirements-3.51.0.json)
contains 3,500 requirements; tests independently hash every full ID. The selected
areas contain 99 datatype, 26 transaction, 17 CREATE INDEX and 21 ALTER TABLE
requirements. Only the last area has public per-requirement Tcl citations (9).

The 3,603,661-byte vendored documentation archive **was supplied by the user** as
`~/Downloads/sqlite-docsrc.tar`, then compressed reproducibly. It is retained with
the generated inventory for offline reproducibility, not required of consumers.
Release: `version-3.51.0`; revision
`93f1a4577785f72b4183843a7c8d33285bc36bce6f6b5258f428a6c844a0099c`.
Original tar SHA256: `f3a39333897823546bca5924899bafaf7f593571863666221e5a38246f065423`.

## Freezing new generic evidence

Run the pinned upstream recorder with `--uncapped --catalog --sample-expressions`.
Catalog mode chooses source-family profiles and controlled clocks; do not combine
it with caller-supplied profile or clock flags. Reports retain the exact source
catalog, actual conditions, sampling identities and every exclusion reason.

The finalizer accepts a complete capture and publishes a new directory:

```sh
python -m conformance.freeze_corpus --input /path/to/capture \
  --upstream /path/to/pinned-upstream --output /path/to/new-corpus \
  --temporary-root /path/to/native-storage \
  --fidelity-ledger /path/to/ledger.json
```

The ledger binds the capture manifest's SHA-256 digest. Its `ledgerVersion` is
`1`; `entries` identify each differing-result refusal by `file`, `id` and
`occurrence`, name its `cause`, and list `evidence` objects with relative `path`
and `sha256`. Every such refusal needs an entry with retained proof bytes.
When there are no differing-result refusals, omit `--fidelity-ledger`.

Freezing adds the fresh authored catalogs, checks final membership and source
hashes, replays all observations natively, and measures the 25 MB current and
60 MB retained budgets. It accounts for every retained v1–v4 directory and
refuses a partial or timed-out source. Original extraction, keyed triage and
proof bytes are retained with digests and verified by ordinary corpus loading.
The command never replaces an existing directory or edits native observations.
Its full native check uses the same explicit storage and resource policy above.
The separate `new-corpus-native-replay.json` receipt retains fixture paths and
unchanged bindings beside the new corpus; it does not change the frozen record
format, execution profiles or membership.

## Historical ADR 0004 measured execution coverage

Run `just conformance-coverage /path/to/llvm-cov build/fresh-coverage-directory`.
On macOS, `xcrun --find llvm-cov` locates the tool. Separate instrumented builds
must preserve ordinary model verdicts/positions and native traces. Existing
counter directories are rejected. Reports bind source, corpus and case digests.

Native counters reset immediately before each migration's prepare/step/finalize,
then dump and reset immediately afterward. Setup, observations and connection
cleanup are excluded, including the automatic process-exit dump. An assertion
rejects leaked fixture open/close/binding function counts. The denominator is
branch arcs in reached functions, not all of SQLite.

Model coverage counts explicit match arms in `step`, `SqlState.finish`,
`literalStep`, `statementReady`, `advance`, `runSqlFrom` and `supportedSqlFrom`.
It does not cover every helper or Boolean branch. Instrumented executables are
measurement tools, never tier-two proof tools; kernel checks use ordinary builds.

The reviewed workload has 104 admitted cases: 88 generated, five original
curated, and 11 from v3. The other 359 corpus cases are excluded from execution
coverage; generated unsupported probes remain separately recorded. Results:
36/41 scoped model arms, 7/7 statement constructors, 7/8 error constructors, and
4,707/14,023 native branch arcs in reached functions.

The [migration-only report](../reports/20260929-adr4-migration-coverage.json)
replaces the headline use of the [historical report](../reports/20260929-adr4-coverage.json),
whose 6,003/16,272 native arcs included harness queries. The denominators are not
comparable. Live measurements are aarch64-darwin; Linux remains for native CI.
Coverage guides further work and does not prove refinement.
