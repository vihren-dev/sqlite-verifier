# ADR 0005: Scale the conformance corpus by roadmap relevance

- Status: Proposed
- Date: 2026-09-30
- Implementation examined: `adr4` workspace at `d9a49d95`
- Decision owners: product owner for corpus scope and storage; formal methods
  lead for extraction fidelity and the progress metric
- Related: [ADR 0004](adr-0004-model-conformance-validation.md),
  [progress and coverage](conformance-progress.md),
  [upstream extraction](upstream-pilot.md)
- This proposal changes test infrastructure only. It does not change supported
  SQL, statuses, the execution profile, or the trust policy.

## Decision in brief

ADR 0004 delivered the pipeline and a frozen sample corpus. The owner decided
to prepare the test suite before further model work and to measure that work
against it. This ADR asks for approval to:

1. Select upstream files by roadmap area, and extract the selected areas without
   a per-file cap.
2. Recover the roadmap-relevant tests the current extraction rules exclude,
   before adding volume.
3. Bound individual case size and store the corpus in the repository as
   per-file shards within a fixed budget.
4. Replay a fixed sample in `just test` and the whole corpus on demand.

Expression-heavy tests (`e_expr.test` and similar) are sampled, not extracted in
full, until the model evaluates expressions.

## 1. Observed problem

Corpus v3 has 370 cases: 341 extracted from 45 upstream files (`alter*.test`,
`e_*.test`) and 29 authored. The extraction saw 21,546 runtime assertions. The
[extraction record](../conformance/corpus-v3/extraction.json.gz) shows three
separate reasons the corpus is small, and they need different remedies.

**The cap hides mostly expression tests.** The cap of 20 cases per file dropped
14,601 candidates; 12,408 of them are in `e_expr.test`, whose loops generate
`SELECT` expression checks. The model has no queries or expression evaluation,
so those cases cannot become agreements before Step 3. Outside `e_expr.test` the
45 files hold 4,928 assertions.

**The files that matter most for the roadmap yield little or nothing.**

| File | Runtime assertions | Recorded | Main exclusion |
| --- | ---: | ---: | --- |
| `e_createtable.test` | 536 | 0 | 404 "connection or SQL callback context"; 78 prefix results differ from Tcl |
| `e_update.test` | 131 | 0 | 119 attached database or nondeterministic function |
| `e_droptrigger.test` | 66 | 0 | 66 connection or SQL callback context |
| `alter.test` | 119 | 12 | 49 attached database; 41 multiple connections |
| `alter3.test` | 59 | 7 | 43 `LEGACY_FILE_FORMAT` outside the profile |
| `e_insert.test` | 203 | 20 | 172 per-file cap |
| `e_fkey.test` | 940 | 20 | 912 per-file cap |

An exclusion currently stays in force until the next `reset_db`, so one
`ATTACH`, one second connection, or one `db onecolumn` call removes every later
test in that stretch of the file. Across all files, 552 candidates were dropped
for "connection or SQL callback context" alone and 446 for attached databases or
nondeterministic functions.

**Relevant files were never scanned.** The pinned source has 1,255 test files.
The patterns cover 45. Files that exercise the current subset and Step 2 are
outside them: `trans*.test`, `savepoint*.test`, `conflict*.test`, `unique*.test`,
`notnull*.test`, `index*.test`, `insert*.test`, `update*.test`, `delete*.test`,
`table.test`, `default.test`, `check.test`, `rowid.test`, `autoinc.test`,
`types*.test`, `affinity*.test`, `without_rowid*.test`, `upsert*.test`,
`fkey*.test`.

Two further facts constrain scaling:

- **Case size is unbounded.** The 370 cases are 308 MB uncompressed because one
  case (`e_blobbytes-1.0`) is 302 MB. The median case is 10 KB and the 90th
  percentile 33 KB. Every per-statement snapshot stores the full state.
- **123 candidates were dropped because the fresh native prefix did not
  reproduce the Tcl results**, 78 of them in `e_createtable.test`. They are
  excluded safely, but nobody has established why.

The resulting baseline is 11 AGREE and 359 MODEL_UNSUPPORTED, with 60 of 182
requirement rows having any case. That is too thin and too skewed to measure
model work against.

## 2. Goals

Give model work a corpus whose unsupported cases are concentrated in the areas
the roadmap enters next, so that extending the model visibly converts cases to
agreements. Keep every excluded candidate accounted for. Keep ordinary
development fast and the repository a reasonable size.

Non-goals: mining the whole upstream suite; extracting multi-connection, fault
injection, corruption, or file-level tests; modelling queries (a separate
roadmap question, see §6).

## 3. Proposed decisions

### 3.1 Select files by roadmap tier

| Tier | Purpose | Files | Policy |
| --- | --- | --- | --- |
| A | Current subset and Step 2: DDL, literal DML, transactions, constraints, indexes | `alter*`, `e_createtable`, `e_insert`, `e_update`, `e_delete`, `e_droptrigger`, `e_dropview`, `e_reindex`, `e_fkey`, plus `trans*`, `savepoint*`, `conflict*`, `unique*`, `notnull*`, `index*` (not `indexexpr*`, `indexedby`), `insert*`, `update*`, `delete*`, `table`, `default`, `check`, `rowid`, `autoinc`, `without_rowid*`, `upsert*`, `fkey*` | Extract every eligible assertion; no per-file cap |
| B | Step 3: expressions, conversions, queries | `e_expr`, `e_select*`, `types*`, `affinity*`, `null*`, `indexexpr*` | Stratified sample: a fixed number per distinct test-name prefix, recorded in the manifest |
| Out | Not comparable to the model | `*fault*`, `*malloc*`, `*corrupt*`, `*auth*`, WAL, URI, blob-handle and FTS files | Excluded by file, with the reason recorded |

The file list is part of the corpus manifest. Moving a file between tiers
creates a new corpus version.

### 3.2 Narrow exclusions before adding volume

Exclusions become as local as the evidence allows. Each change needs a test that
the narrowed rule still rejects the cases it exists for.

- **Row-returning helper calls.** `db onecolumn`, `db exists`, and `db eval`
  with a row script only read results differently. The SQL is recorded as an
  ordinary statement. A row script that itself runs SQL or Tcl with side effects
  remains an exclusion.
- **Attached databases.** An `ATTACH` excludes tests until the matching `DETACH`
  or the next reset, not to the end of the stretch. Tests that reference the
  attached schema stay excluded.
- **Second connections.** A second connection excludes tests while it is open
  and restores eligibility after it closes, provided it executed no write.
- **Nondeterministic functions.** Only tests whose own SQL or prefix uses them
  are excluded; the recorder already requires exact repeat replay.
- **Profile settings.** `LEGACY_FILE_FORMAT` and other settings outside the
  profile stay excluded; the count is reported per setting.

Acceptance is a before/after yield table for the files in §1, with every
remaining exclusion reason counted.

### 3.3 Bound case size

A case whose uncompressed record exceeds 1 MB is excluded with the reason
"case size limit" and its measured size. Snapshots within one case are stored
once per distinct content and referenced by digest, since most statements leave
most tables unchanged. The record format version increases; versions 1 and 2
remain readable.

### 3.4 Storage

The corpus stays in the repository, as one compressed shard per upstream file
plus one for authored cases, under `conformance/corpus-vN/`. The budget is
25 MB compressed for the current version and 60 MB across retained versions.
The manifest binds each shard's digest.

At v3's ratio of roughly 1.7 KB compressed per case, tier A is expected to fit
well inside that budget; this is an estimate until §3.2 yields are measured. If
a version would exceed the budget, the excess tier B shards move to a release
asset fetched by Nix with a fixed hash, and the manifest records the split.
Superseded versions older than the two most recent are removed from the working
tree; their digests stay in the manifest history.

### 3.5 Replay tiers

- `just test` replays a fixed stratified sample: every authored case and a
  bounded number per tier A shard, within 60 seconds.
- `just conformance-progress` replays the whole current version and writes the
  progress report. It runs on demand and before each model change is merged.
- The progress report states counts per tier and per shard, so tier B's
  unsupported cases do not dilute tier A's progress.

### 3.6 Fidelity triage

Every candidate dropped for differing prefix or assertion results is assigned a
cause: a formatting limitation of the Tcl comparison (REAL, BLOB, encoding),
state the prefix cannot reproduce (temporary objects, connection state), or a
real nondeterminism. Causes in the first group are fixed where the fix is
mechanical; the rest stay excluded with the named cause. No native record is
edited to match Tcl output.

### 3.7 Authored cases and mutants

Authored cases target requirement rows that still have no case after tier A
extraction, starting with `lang_transaction`, `lang_createindex`, and the
`datatype3` rows the current subset can express. The mutation set grows with
each model change: at least the NOT NULL check, the column limit, the
duplicate-table check, and the two transaction-state errors are added now.

## 4. Assumptions and limits

- Extraction is not reproducible byte for byte, because upstream tests generate
  data at run time. A corpus version is a frozen artifact bound by digests, not
  something rebuilt from source hashes.
- Yield after §3.2 is unknown. Narrowed rules could admit cases whose native
  replay still fails; those remain exclusions with their reasons.
- Replay time for a larger corpus is unmeasured. The 60-second sample budget is
  a requirement; the full replay time is reported, not bounded by this ADR.
- A larger corpus raises MODEL_UNSUPPORTED counts. That is the intended
  baseline, not a regression.

## 5. Alternatives considered

**Raise the cap only.** Rejected: 85% of what the cap hides is `e_expr.test`,
and the files that matter are limited by exclusions and patterns instead.

**Extract every upstream file.** Rejected: most files test the pager, WAL, VFS,
fault injection, or the C API, which the model does not describe.

**Host the corpus outside the repository from the start.** Deferred: it adds a
fetch step and an availability dependency for a corpus that is expected to fit
in the budget. §3.4 keeps it as the overflow path.

**Regenerate the corpus in CI instead of freezing it.** Rejected: extraction is
not deterministic, and a moving denominator cannot measure progress.

## 6. Open question for the owner: read-only queries

Many upstream tests check their result with a trailing `SELECT`. The progress
diagnostic already separates those queries from the migration, and in v3 no case
is blocked only by its trailing query. After tier A extraction that count may
grow. If it does, modelling a minimal read-only query (plain column selection
from one table in rowid order) would let the model confirm the upstream
assertion itself, not only the state snapshot. This ADR does not propose it; the
tier A report will show how many cases it would unlock.

## 7. Work packages

| Package | Depends on | Completion evidence |
| --- | --- | --- |
| C1: exclusion narrowing | None | Before/after yield table for the §1 files; each narrowed rule has a rejecting test; every remaining exclusion counted |
| C2: case size bound and snapshot sharing | None | New record version; the 302 MB case excluded with its size; v1–v3 still replay; median and maximum case size reported |
| C3: fidelity triage | C1 | Every differing-result candidate has a named cause; mechanical causes fixed |
| C4: tier A extraction and corpus v4 | C1, C2, C3 | Per-file shards, manifest with tier list and digests, exclusion record, native replay of every case, size within budget |
| C5: replay tiers | C4 | `just test` sample within 60 seconds; full replay time reported; progress report per tier and shard |
| C6: tier B sample | C4 | Stratified `e_expr`/`e_select*`/`types*` sample with the selection rule in the manifest |
| C7: authored cases and mutants | C4 | Requirement rows with cases reported before and after; added mutants all killed at the fixed seed |

Each package follows the repository task/status file process. C1 and C2 can
proceed in parallel.

## 8. Rollout and rollback

Corpus v3 stays the frozen baseline until v4 replays natively and its progress
report is committed. Model changes are measured against one corpus version at a
time. Rollback keeps the previous version as current; extraction rule changes
are ordinary commits and can be reverted without touching frozen records.
