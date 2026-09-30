# ADR 0005: Build the conformance corpus for a reference workload

- Status: Proposed (revised 2026-09-30; replaces the first draft, which selected
  tests by roadmap area and deferred query and expression tests)
- Date: 2026-09-30
- Implementation examined: `adr4` workspace at `d9a49d95`
- Decision owners: product owner for corpus scope, profiles and storage; formal
  methods lead for extraction fidelity, the case format and the progress metric
- Related: [ADR 0004](adr-0004-model-conformance-validation.md),
  [progress and coverage](conformance-progress.md),
  [upstream extraction](upstream-pilot.md),
  [case format v1](conformance-format-v1.md),
  [execution profile](execution-profile.md)
- This proposal changes test infrastructure and adds execution profiles for
  testing. It does not change the SQL the verifier supports or the trust policy.

## Decision in brief

The owner decided that the test suite is completed before the model is
extended, and that the target is a reference workload: one real SQL-first
application whose statements and migrations the model must cover. This ADR asks
for approval to:

1. Extend the case format and the native recorder to **statement outputs and
   parameters**, not only stored state.
2. Record and replay every case under an **explicit execution profile**, and
   add the profile the reference workload runs under.
3. Freeze a corpus that contains the workload's **actual statements and
   migrations**, plus boundary and interaction cases and the upstream tests for
   the SQL features it uses. The workload's own data is kept **outside this
   repository** and supplied to the tooling.
4. Narrow the extraction rules that exclude relevant upstream tests, bound case
   size, store the corpus as per-file shards within a fixed budget, and replay
   a sample in `just test`.

The model work is then measured against this corpus: cases move from
unsupported to agreeing, with no disagreements.

## 1. Observed problem

### 1.1 The format cannot check what a query returns

[Case format v1](conformance-format-v1.md) observes, after each statement, the
stored tables, the transaction status and the primary error code. It does not
record the rows a `SELECT` returns, the rows a write returns through
`RETURNING`, or the affected-row count, and it has no parameters. A model could
agree with every v1 case while computing wrong query results. The translator-
independent native records from ADR 0004 already keep result rows, but
`classifyCase` does not compare them.

### 1.2 There is one execution profile

[The supported profile](execution-profile.md) is a pinned default build with
default connection settings, deferred transactions and no foreign-key
enforcement. A real application differs on each of these. The reference
workload:

- bundles SQLite through Go drivers whose version and compile options are not
  the pinned 3.51.0 build;
- sets `foreign_keys=ON`, which changes statement behavior (cascading deletes),
  along with settings that do not (`journal_mode`, `synchronous`, cache sizes);
- uses `BEGIN IMMEDIATE` and groups statements in application-level
  transactions;
- reads the clock through `'now'`, an input from outside the database;
- shares the database with its migration tool's bookkeeping table.

Without a stated profile shared by recording and replay, "the model covers the
workload" has no fixed meaning.

### 1.3 The workload needs SQL the corpus does not target

| Area | What the workload uses |
| --- | --- |
| Schema | Triggers, foreign keys with `ON DELETE CASCADE`, `CHECK` constraints, defaults, `TEXT PRIMARY KEY`, indexes, added columns |
| Statements | `SELECT` with `ORDER BY`, `LIMIT`, `GROUP BY`; `COUNT`, `SUM`, `AVG`, `MAX`; `COALESCE`, `CAST`; `RETURNING`; `JOIN`; `ON CONFLICT` |
| Functions | Current time, date formatting, `json_extract`, `json_each` |
| Values | `REAL` arithmetic |

The first draft of this ADR treated query and expression tests as a later tier
to be sampled. They are now required.

### 1.4 The extraction is small for reasons other than the cap

Corpus v3 has 370 cases from 45 upstream files and 21,546 runtime assertions.
The [extraction record](../conformance/corpus-v3/extraction.json.gz) shows:

- **The cap hides mostly expression tests.** Of 14,601 candidates dropped by the
  cap of 20 per file, 12,408 are in `e_expr.test`.
- **Exclusions are too broad.** An exclusion stays in force until the next
  `reset_db`. `e_createtable.test` yields 0 of 536 (404 for "connection or SQL
  callback context"), `e_update.test` 0 of 131 (119 after an `ATTACH` or a
  nondeterministic function), `alter.test` 12 of 119.
- **Relevant files were never scanned.** Only 45 of 1,255 upstream files match
  the patterns; `trigger*`, `fkey*`, `select*`, `aggregate`-related, `date*`,
  `json*`, `cast`, `returning*`, `upsert*`, `trans*`, `insert*`, `update*` and
  `delete*` files are outside them.
- **Case size is unbounded.** The 370 cases are 308 MB uncompressed because one
  case is 302 MB; the median is 10 KB.
- **123 candidates were dropped because a fresh native prefix did not reproduce
  the Tcl results**, with no established cause.

## 2. Goals

Give the model work a frozen corpus that checks statement outputs under the
workload's real execution conditions, whose unsupported cases are the SQL the
workload needs. Keep every excluded candidate accounted for, ordinary
development fast, and the repository a reasonable size.

Non-goals: mining the whole upstream suite; multi-connection, fault-injection,
corruption or file-level tests; extending the model (that follows, measured by
this corpus).

## 3. Proposed decisions

### 3.1 Case format v2: outputs and parameters

Each executed statement records, in addition to v1's observations:

- **bound parameters**, as typed values;
- **result rows**, typed, in the order SQLite returned them, with a flag saying
  whether the statement fixes that order (`ORDER BY` covering a unique key) or
  the rows compare as an unordered collection;
- **`RETURNING` rows** for writes;
- **the affected-row count** (`sqlite3_changes`).

`classifyCase` compares these as well as state. A case whose outputs the model
cannot produce is `MODEL_UNSUPPORTED`, never an agreement. v1 cases remain
readable and keep their verdicts.

### 3.2 Execution profiles

A profile is a named, versioned record stored with each corpus:

| Dimension | Content |
| --- | --- |
| Engine | SQLite version, source ID and compile options |
| Connection settings | Those that change statement behavior, such as `foreign_keys` and `recursive_triggers`; settings that do not are listed as ignored, with the reason |
| Transactions | The transaction mode, and which statement sequences a case runs as one unit |
| External inputs | The clock value each statement sees. The recorder fixes or records it, so replay is deterministic |
| Other writers | Objects outside the contract, such as a migration tool's bookkeeping table, and what is assumed about them |

The recorder refuses to run under a profile it cannot establish and verify on
the connection, as it already does for the current one. Recording and replay
use the same profile; a case recorded under one profile is never replayed under
another.

The workload's engine is measured first: the SQLite version and compile options
of each driver it ships are read from the running drivers. If they differ from
a pinned build in a way that affects the workload's SQL, a pinned build for
that version is added, as was done for 3.46.0. Until that measurement exists,
the corpus states that it was recorded on the pinned build and that the gap to
the workload's engines is unmeasured.

### 3.3 Corpus content

| Part | Content | Policy |
| --- | --- | --- |
| Workload | Every statement and migration of the reference workload, with typed parameter values and recorded outputs | All of them; this part defines "covers the workload". Stored outside this repository (§3.3.1) |
| Boundary and interaction | Triggers firing on writes, cascading deletes, constraint failures, statements grouped in one transaction, NULL and empty values, numeric edge values, empty and single-row tables | Authored, one or more per statement and per interaction |
| Upstream, by feature | Upstream tests for the features in §1.3 | Extracted without a per-file cap after §3.4; loop-generated expression tests sampled by test-name prefix |
| Out | `*fault*`, `*malloc*`, `*corrupt*`, `*auth*`, WAL, URI, blob-handle and FTS files | Excluded by file, with the reason recorded |

#### 3.3.1 Workload data stays outside this repository

A reference workload is a use case, not part of the core. This repository
contains the tooling, the formats, the profiles' definitions, and the generic
corpus parts (boundary cases written against neutral schemas, and upstream
tests). It does not contain a workload's SQL, its name, its recorded cases or
its results.

- The recorder, replay and progress commands take the workload's location as an
  argument: a directory with the schema and query files, a profile record, and
  the workload corpus shard with its manifest.
- A workload manifest binds its shard by digest and names the corpus format
  version and profile it was recorded under, so the core can refuse a mismatch.
- `just test` and CI in this repository run without any workload. Workload
  replay is a separate command, run where the workload data is available.
- A small synthetic workload lives in this repository to test the mechanism: a
  few tables, statements with parameters, a trigger and a foreign key.

The feature table sets coverage categories. The denominator is the frozen
corpus itself: the generic parts in this repository plus the workload shard. The file list and sampling rule are part of the manifest;
changing them creates a new corpus version.

### 3.4 Narrow exclusions before adding volume

Each change needs a test that the narrowed rule still rejects what it exists
for.

- **Row-returning helper calls** (`db onecolumn`, `db exists`, `db eval` with a
  row script) are recorded as ordinary statements. A row script with side
  effects remains an exclusion.
- **Attached databases** exclude tests until the matching `DETACH` or reset.
- **Second connections** exclude tests while open, and restore eligibility
  after closing if they wrote nothing.
- **Nondeterministic functions** exclude only tests whose own SQL or prefix uses
  them. Clock reads are handled by the profile instead.
- **Settings outside every supported profile** stay excluded, counted per
  setting.

### 3.5 Case size, storage and replay

- A case over 1 MB uncompressed is excluded as "case size limit". Snapshots
  within a case are stored once per distinct content and referenced by digest.
- The corpus stays in the repository as one compressed shard per source, within
  25 MB for the current version and 60 MB across retained versions. Overflow
  moves to a release asset fetched by Nix with a fixed hash.
- `just test` replays the synthetic workload, every authored case and a bounded
  sample of the rest, within 60 seconds. The reference workload is replayed by
  its own command. `just conformance-progress` replays everything
  and reports per part, per feature and per shard.

### 3.6 Fidelity triage, authored cases and mutants

Every candidate dropped for differing results gets a named cause; mechanical
causes are fixed, and no native record is edited to match Tcl output. Authored
cases also cover requirement rows with no case. The mutation set grows with the
model and gains output mutants (a wrong result row, a wrong count).

## 4. Assumptions and limits

- Passing the corpus shows agreement on those cases under that profile, not
  equality with SQLite.
- The workload's own statements carry no independent expectation: their
  outputs are whatever the pinned engine produced for the chosen parameters.
  The boundary and upstream parts supply variety.
- Extraction is not reproducible byte for byte; a corpus version is a frozen
  artifact bound by digests.
- Yield after §3.4, replay time, and corpus size are unmeasured.
- A larger corpus raises `MODEL_UNSUPPORTED` counts. That is the intended
  baseline.

## 5. Alternatives considered

**Keep comparing stored state only.** Rejected: the model could agree on every
case and still return wrong query results.

**One profile for all cases.** Rejected: foreign-key enforcement alone changes
what the workload's deletes do.

**Keep the reference workload's data in this repository.** Rejected by the
owner: a workload is a use case, and the core stays free of it.

**Record under the workload's own drivers.** Deferred: it would tie the corpus
to a Go toolchain and two engine builds. §3.2 measures the gap first.

**Raise the cap only, or extract every upstream file.** Rejected, as in the
first draft: the cap mostly hides one file, and most upstream files test
behavior the model does not describe.

**Regenerate the corpus in CI.** Rejected: extraction is not deterministic, and
a moving denominator cannot measure progress.

## 6. Work packages

| Package | Depends on | Completion evidence |
| --- | --- | --- |
| C0: format v2 and recorder outputs | None | Parameters, result rows, `RETURNING` rows and change counts recorded and compared; an output mutant is caught; v1 cases keep their verdicts |
| C1: execution profiles | None | Profile record in the manifest; the workload profile established and verified on the connection; a case refuses replay under another profile; clock fixed or recorded; engine versions of the workload's drivers measured |
| C2: exclusion narrowing | None | Before/after yield table for the §1.4 files; each narrowed rule has a rejecting test |
| C3: case size bound and snapshot sharing | C0 | The 302 MB case excluded with its size; earlier versions still replay |
| C4: fidelity triage | C2 | Every differing-result candidate has a named cause |
| C5: corpus v4 and external workloads | C0–C4 | Boundary and upstream parts frozen in this repository; the synthetic workload recorded and replayed from an external-style directory; a manifest mismatch in format or profile is refused; size within budget; native replay passes |
| C6: replay tiers and baseline report | C5 | `just test` sample within 60 seconds; progress report per part and feature; the baseline for the model work |
| C7: authored requirement cases and mutants | C5 | Requirement rows with cases before and after; added mutants killed |

C0, C1 and C2 can proceed in parallel. Each package follows the repository
task/status file process.

## 7. Rollout and rollback

Corpus v3 stays the frozen baseline until v4 replays natively and its report is
committed. The existing profile and v1 format remain supported. Rollback keeps
the previous corpus version as current; format and extraction changes are
ordinary commits and can be reverted without touching frozen records.
