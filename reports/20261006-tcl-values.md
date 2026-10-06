# Exact Tcl values: paired date-family validation

Status: acquisition evidence complete; full model validation pending. Created
2026-10-06. Audience: the team and reviewers.

Task: [T17](../plans/20261006-exact-tcl-values.task.md).
Source: [issue #35](https://github.com/vihren-dev/sqlite-verifier/issues/35).
Machine record: [summary.json](20261006-tcl-values/summary.json).

The fixed cohort accepted 95 of 100 occurrences after typed binding capture,
compared with 55 before it. The 40 recovered occurrences are the first 20 in
`date4.test` and the first 20 in `date5.test`. All 95 accepted cases pass fresh
native replay. Five `date2.test` occurrences still exceed the existing case-byte
limit. No accepted occurrence was lost.

| Source | All runtime occurrences | Cohort occurrences | Before accepted | After accepted |
|---|---:|---:|---:|---:|
| `date.test` | 1,683 | 20 | 20 | 20 |
| `date2.test` | 29 | 20 | 15 | 15 |
| `date3.test` | 126 | 20 | 20 | 20 |
| `date4.test` | 24,859 | 20 | 0 | 20 |
| `date5.test` | 874 | 20 | 0 | 20 |
| Total | 27,571 | 100 | 55 | 95 |

## Source inputs and comparison

Each of the five pinned SQLite 3.51.0 files ran once through the real Tcl
`testfixture`. All executions returned zero and produced a complete event
stream. Capture used the catalog clock profile, Unix time 1,700,000,000 seconds,
UTC, foreign keys off and recursive triggers off. The source can change its own
Tcl precision; the first cohort calls in `date.test` and `date3.test` retain their
observed precision 15. Each source execution has a 60-second timeout.

The two acquisition revisions consume the same retained events through a
validation-only subprocess adapter. The adapter replaces only the already
executed Tcl source command; engine identity checks, native recording, result
comparison, prefix minimization and fresh native replay still execute normally.
The adapter checks the original capture conditions. The exact used driver
texts are retained in [used-validation-drivers.json.gz](20261006-tcl-values/used-validation-drivers.json.gz).

The before revision is `bf78762bd7a6cdb451d41d7a8c8df2dc1394ffb0`. It already
contains the precision fix. Capture used
`e6293cfce0221ff87af8192143a59e753f04f529`; after classification used
`ab78f7c20e26519853f1eb01e3fe1e1de77c70e3`. The final diagnostic cleanup is
`331467e9d64b478ac9889053381c2462b7365085`. The capture, before and after
manifests retain the full extractor hashes, source hashes, engine source ID,
compile options and fixture hash. The later cleanup removes an unreachable
exception wrapper and does not change these source inputs or acceptance.
The later source SQL encoding guard is
`d4eb312a615ea2d59c52736dd2cc19bc86171ac6`. All 1,050 original SQL/setup
appearances in the 100 paired occurrences are ASCII without NUL. The guard
therefore adds no cohort refusal. The artifacts retain their actual acquisition
revisions.

[paired-inputs.jsonl.gz](20261006-tcl-values/paired-inputs.jsonl.gz) contains all
100 original input objects and their before/after dispositions. The objects
include original setup, SQL, helpers, expected display, per-call results, return
codes, precision and NULL markers. Both parsers independently reproduced the
same input hash for every pair: **zero paired original inputs changed**. The
record also contains observed typed `sourceCalls`, original object metadata and
call digests. Repeated values and setup inputs stay attached to their source and
runtime occurrence.

The cohort consists of the first 20 runtime occurrences per file, chosen before
native acceptance. It is not a quota of the first 20 successful acquisitions.
The full manifests retain all 27,571 dispositions. Every one of the 27,471
outside-cohort occurrences has an explicit cohort refusal, together with any
other observed refusal. These counts do not establish full-family yield.

## Remaining refusals and checks

Within the cohort, the only remaining refusal is the case-byte limit in five
`date2.test` occurrences. Before binding capture, `date4.test` refused observed
`$::FMT` and `$::TS`; `date5.test` refused the accumulated `$::jd`, `$::date`,
`$::jd2` and `$::date2` inputs. The after evidence retains their actual TEXT or
numeric storage classes, bytes and REAL bits for each original call.

Outside the cohort, `date.test` also retains source clock changes, local-time
fault controls and application function callbacks as refusals. Those contexts
have not been approximated. Both acquisition manifests retain each occurrence,
its full reason list and all reason denominators.

[input-corruption.json](20261006-tcl-values/input-corruption.json) records an
actual value-dependent `date5.test` check. Changing `$::jd` from numeric-looking
TEXT `2460369.5` to TEXT `2460370.5`, updating both binding copies and recomputing
the source-call digest still fails fresh replay against the original
`2024-02-29` result. Exact REAL bit corruption and signed-zero checks are covered
by the pinned Tcl regression suite.

Tcl NUL and CESU-8 bytes remain exact in typed binding evidence and native
storage/hex checks. The display comparator accepts standard UTF-8 TEXT; direct
TEXT output outside that codec has a named source refusal. No output bytes are
normalized and no missing parameter becomes a guessed NULL. Source SQL whose
Tcl bytes differ from the UTF-8 event transport has a named refusal, including
`typeof` queries whose result would otherwise conceal changed SQL bytes.

A separate [codec fixture record](20261006-tcl-values/codec-summary.json)
retains actual pinned Tcl execution of the committed authored regression source.
Its 21 occurrences include 11 accepted cases, all passing fresh native replay.
The original typed TEXT bytes are `C080` for NUL and `EDA0BDEDB880` for the
non-BMP character. Storage-class/hex assertions pass; direct displays and source
SQL outside the event codec retain their named refusals. These authored cases
are separate from the date-family denominator. Their full acquisition, event
stream and cases are retained in the artifact list.

The historical frozen v5 date dispositions are included in the summary as a
separate reference. Its source hashes and runtime counts match, but its random
history and individual captured inputs are not claimed identical to this run.
No frozen v1–v5 artifact changed. The paired delta measures binding capture;
the precision fix is checked independently with actual precision-15 Tcl cases.

The final sandboxed upstream target passes all 104 tests in 2.84 seconds, with
no skips. Its JUnit path is recorded in the summary. The affected transport and
fidelity regressions also pass independently under a 90-second bound.

This record establishes source acquisition and native replay. It makes no
claim of model agreement or added production date-function support. The task
remains IN PROGRESS until the coordinated full model gate is complete.

## Retained artifacts

[summary.json](20261006-tcl-values/summary.json) lists each compressed and
uncompressed SHA-256 and byte count. The five complete source event streams,
stdout and stderr are retained alongside [capture.json.gz](20261006-tcl-values/capture.json.gz).
The before/after manifests keep every original disposition:
[before-acquisition.json.gz](20261006-tcl-values/before-acquisition.json.gz) and
[after-acquisition.json.gz](20261006-tcl-values/after-acquisition.json.gz).

The unchanged recorded cases are
[before-cases.jsonl.gz](20261006-tcl-values/before-cases.jsonl.gz) and
[after-cases.jsonl.gz](20261006-tcl-values/after-cases.jsonl.gz). Decompress the
matching acquisition manifest to `manifest.json` and use the case file as
`cases.jsonl.gz` to load or replay either artifact with its corresponding
revision. For paired reproduction, decompress the capture artifacts to their
original names and run the retained replay driver with `--root`, `--capture`
and `--output`, using the fixture and upstream paths recorded in the capture
manifest. Keep the first-20 cohort and all capture conditions unchanged.
