# Exact Tcl values status

Status: IN PROGRESS. Created 2026-10-06.

Task: [exact Tcl values and date-family acquisition](20261006-exact-tcl-values.task.md).
Issue: [#35](https://github.com/vihren-dev/sqlite-verifier/issues/35).
Specifications: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md),
[native output and parameters](../docs/conformance-format-v2.md).

Relevant files: `conformance/upstream_result_values.py`,
`conformance/upstream_proxy.tcl`, `conformance/upstream_assertions.py`,
`conformance/upstream_selection.py`, `conformance/upstream_fidelity.py`,
`conformance/native_record.py`, `conformance/native_statements.py`,
`conformance/native_library.py`, `conformance/corpus.py`.

## Progress

- 2026-10-06: Created an isolated workspace on reviewed T16 tip `5de5cba90fbf`.
  T16 evidence and its pending journal entry remain intact in their workspace.
  Read issue #35 (no comments), existing comparator/binding guards, and pinned
  SQLite source. `date.test` and `date3.test` set precision 15. `date4.test` and
  `date5.test` use observed Tcl scalar bindings. The actual binder distinguishes
  Tcl integer/double objects from numeric-looking text and can force BLOBs with
  an `@` slot name.
- 2026-10-06: Specified exact round-trip acceptance and narrowly scoped typed
  setup/call binding evidence before coding. Investigation and short checks may
  run now; long acquisition/full-model runs wait for host coordination.
- 2026-10-06: Added precision policy v2. Captured precision 0–17 can accompany
  exact REAL comparison; all successful REAL displays must still round-trip to
  the native bits. Historical policy v1 retains its precision-zero guarantee.
  The pinned Tcl 8.6.16 runtime independently confirmed the accepted precision
  range and big-endian double encoding used by later binding observation.
- 2026-10-06: Actual Tcl regression covers precision 15, date arithmetic, signed
  zero, adjacent REAL values with identical rounded text, changed per-call
  precision, and one-bit evidence corruption. The focused precision/value,
  acquisition and freeze checks passed 93 tests in 3.78 seconds (90-second
  bound). A separate retained-policy load/replay check passed in 0.54 seconds
  (30-second bound). Bindings remain unimplemented at this checkpoint.
- Automatic approval review timed out before the first short test command
  started. The permitted single retry ran successfully; no test was bypassed.
- The sandboxed upstream target passed all 69 tests in 2.81 seconds, with no
  skips. JUnit: `/nix/store/09an84cnqr6hxahvgdddd6gc1x47p0xw-sqlite-verifier-test-upstream-1/junit.xml`.
  The new precision module is owned by this target. All frozen artifacts remain
  unchanged, and the retained-policy regression explicitly rejects precision
  15 when relabeled as historical policy v1.
- 2026-10-06: Centralized the retained Tcl precision-policy versions beside the
  acquisition policy. Both historical readers use this declaration. Resolved
  independent review finding `20261006T125917Z-2950f417#1`. The same 94 focused
  precision/value, acquisition and freeze checks passed in 2.94 seconds under
  a 90-second bound, using the existing pinned Python/Tcl/native tools.
- 2026-10-06: Implemented observed scalar binding capture and native binding
  recording version 1. The observer reads actual Tcl object types before
  formatting, preserves original objects and encoded bytes, and refuses missing
  values, traces, source callbacks, array forms, mixed `@` conversions, NaN
  bindings and bound row-script contexts. Actual Tcl checks compare source
  execution with and without the observer, including string-representation
  state, numeric-looking TEXT, signed zero, changed values, NUL and non-ASCII
  bytes. Source callbacks and variable read traces run once in both executions.
- Native replay checks SQLite's actual slot names and counts, including repeated
  names. Typed setup vectors, helpers, read-only guards and original source call
  references remain paired through minimization. The explicit setup primitive
  still supports anonymous/numbered slots and directly supplied NULL values.
  Malformed metadata and coherently corrupted input copies fail before model
  admission or fresh observation comparison. Both corpus loaders enforce the
  new extension; model/profile support and frozen v1–v5 bytes remain unchanged.
- New acquisition reports use version 2 and bind original call contexts by
  SHA-256 in each accepted source instance. Original SQL, expectations, return
  codes, per-call precision, NULL markers, typed values and object metadata remain
  in `sourceCalls`, before minimization. Historical acquisition version 1 retains
  its refusal boundary and replay shape.
- The current TEXT display comparator accepts standard UTF-8. Tcl's encoded
  NUL and other nonstandard display bytes remain exact in binding evidence and
  native storage/hex replay; direct displays that the comparator cannot decode
  retain a named refusal with the source identity. No bytes are normalized.
- The final focused batch passed 174 tests in 12.87 seconds (90-second bound),
  including historical v1 replay through the existing compiled runtime. The
  final policy extraction passed 21 binding checks in 0.71 seconds. The
  sandboxed upstream target passed 90 tests in 2.89 seconds without skips.
  JUnit: `/nix/store/wa0ggvihd31ql0mzig62p1l19pkp7s7b-sqlite-verifier-test-upstream-1/junit.xml`.
  The native audit also passed 205 short checks, with its one full-model case
  deferred for host coordination. Date-family acquisition evidence and the full
  model gate remain pending; this task is not DONE.
- 2026-10-06: Independent review of binding checkpoint `c86453d8` found five
  `should` findings and no `must` findings. Added relabel/removal damage checks,
  typed replay keyword arguments, a shared read-only helper policy, required
  current binding observations without the obsolete token fallback, and
  diagnostics that preserve the case name, failing fields and recapture action.
  Resolved findings `20261006T143036Z-c86453d8#1` through `#5`. The refactor passed
  195 focused checks in 9.03 seconds (90-second bound), and the sandboxed upstream
  target passed 100 tests in 2.90 seconds without skips. JUnit:
  `/nix/store/v8b84fkv9myw7xas2pbv9zc2r8s6kk7a-sqlite-verifier-test-upstream-1/junit.xml`.
- 2026-10-06: Review of refactor `fc354847` found three further `should`
  findings and no `must` findings. Fidelity differences now say to exclude the
  source assertion; recapture advice applies only to damaged binding fields.
  One documented predicate covers both auxiliary and scalar read-only helpers,
  and the unreachable shard exception wrapper was removed. Resolved
  `20261006T144842Z-fc354847#1` through `#3`. The changes passed 196 focused
  checks in 9.13 seconds and 101 sandboxed upstream checks in 3.00 seconds, with
  no skips. JUnit:
  `/nix/store/xdaa2jqsjjg5v8wy95nn547zvcrm63yf-sqlite-verifier-test-upstream-1/junit.xml`.
- 2026-10-06: Review of `e6293cfc` found one remaining diagnostic `should`:
  missing or misaligned setup results could reach the fidelity wrapper before
  their structure was checked. Added setup-result and trace-result shape checks
  and missing/length/row damage regressions. The 39 affected binding/precision
  checks passed in 0.66 seconds (90-second bound). Resolved
  `20261006T145940Z-e6293cfc#1`.
- Started bounded paired date-family validation after localhost was released.
  All five pinned source files completed their actual Tcl execution with exit
  zero. One retained source event stream feeds both the pre-binding checkpoint
  and the current implementation. Selection uses the first 20 runtime
  occurrences per file, independently of native acceptance, and accounts for
  all outside-cohort refusals. This comparison measures the binding change;
  the pre-binding checkpoint already includes the earlier precision fix.
- 2026-10-06: Removed the now-unreachable fidelity wrapper for structural
  exceptions after review `20261006T150923Z-ab78f7c2#1`. The preceding transport
  checks already reject those inputs with case/field diagnostics. The 39 affected
  regressions passed in 0.61 seconds (90-second bound).
- The fixed 100-occurrence date cohort recovered 95 cases, compared with 55 at
  the pre-binding checkpoint: the first 20 `date4.test` and first 20 `date5.test`
  occurrences now retain their observed values and pass native acquisition.
  The five remaining cohort refusals are the existing case-byte limit in
  `date2.test`. All 27,571 source instances remain accounted for, including
  27,471 explicitly outside the validation cohort. This is bounded validation,
  not a claim of full-family acquisition or model support.
- 2026-10-06: Separated the complete-freeze capture fixture from its acceptance
  checks. The updated test had grown from 199 to 209 lines with binding evidence;
  both files now remain below 200 lines. The fixture is an explicit Nix model
  input. All 28 existing freeze checks pass under a 90-second bound. The
  reviewed diagnostic cleanup `331467e9` has no findings. The paired acquisition
  artifacts are ready in the working copy and will be recorded separately.
- 2026-10-06: Fixture extraction `ef3ff4cc` passed independent review with no
  findings. Updated the evidence-test caller to import the flat fixture module
  directly and declared that module in both upstream and model Nix inputs. The
  53 affected freeze/evidence checks pass in 5.16 seconds (90-second bound).
  The upstream sandbox target passes 104 checks in 2.67 seconds without skips;
  JUnit: `/nix/store/25c4wdbj0h5kpk8xwi3gdvn7s50dswdp-sqlite-verifier-test-upstream-1/junit.xml`.
  The separate T04b storage caller must use the same direct import at assembly.
