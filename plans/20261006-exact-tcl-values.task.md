# Exact Tcl values and date-family acquisition

Status: IN PROGRESS. Created 2026-10-06.

## Outcome

New acquisition accepts a source's observed Tcl display precision, including
15, only when each successful REAL display parses back to the exact independently
recorded IEEE value. Two different REAL values that share rounded display text
are not treated as equal. Signed zero remains distinct. Original source SQL,
expectations and per-call precision remain in the evidence. Unobserved precision,
variable traces and other unobservable formatting contexts retain named refusals.
Source SQL bytes must survive the event codec unchanged; other SQL encodings
retain a named refusal, including queries whose output would hide the change.

Safely observable Tcl parameters retain their actual SQLite storage class and
value for each SQL call, including calls in setup prefixes. Repeated slot names
and values changed between calls replay faithfully. Missing variables never
become guessed NULLs. Source callbacks, variable traces, unsupported variable
forms and other unobservable bindings stay refused with a reason.

Fresh native replay binds the retained values at the original call boundaries
and verifies actual SQLite slot names and counts. The existing typed-cell codec
is used for integer, REAL bits, text, BLOB and directly observed NULL values.
New native evidence must retain typed setup bindings and the per-call binding
context needed for replay; that narrowly scoped recording addition is part of
this task. Malformed or incomplete binding metadata is refused. Existing
profile semantics, production SQL support, acquisition random-seed policy and
frozen v1–v5 artifacts stay unchanged.

Source: [issue #35](https://github.com/vihren-dev/sqlite-verifier/issues/35).
Specifications: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md),
[native output and parameter format](../docs/conformance-format-v2.md).

## Acceptance

Actual pinned Tcl cases cover source-owned precision 15, an exactly representable
REAL, two distinct REALs with the same rounded display, signed zero, date
arithmetic, named parameter values, integer/text/BLOB storage classes, values
changed between calls, and setup data needed by a later assertion. Missing and
traced variables and callback-dependent bindings remain named refusals. Checks
also cover parameter-like text in SQL comments and quoted strings.

Acquired cases pass independent native replay with the original SQL. Corrupting
one REAL bit or a parameter value in representative value-dependent cases fails
fresh replay. Observed precision and typed parameter evidence remain attached to
the original source/occurrence identities. Tests verify malformed slot metadata
and missing values cannot silently bind NULL.

New date-family evidence retains source and extractor revisions, actual case
input identities, before/after dispositions and every remaining refusal. Any
bounded cohort or sampling policy is explicit; independent captures are not
described as identical inputs. Relevant short native/Tcl tests and the pinned
upstream suite pass with timeouts. Long acquisition and full-model runs wait for
host coordination. Independent review outcomes remain in the append-only journal.

## Constraints and relevant code

`upstream_result_values.values_agree` already compares REAL bits; observed
nonzero precision must not bypass that comparison. `upstream_proxy.tcl` currently
refuses source precision changes and captures per-call formatting metadata.
`upstream_assertions.iter_assertions` owns ordered setup and assertion calls.
`upstream_selection` refuses every uncaptured named slot.

The pinned `tclsqlite.c` binder chooses types from the actual Tcl object and
parameter name. Numeric-looking text must not be guessed to be numeric. Binding
observation must not invoke application callbacks or variable traces, or change
the value/type before source execution. `native_statements.execute` and
`native_record.record_sql` already support typed assertion parameter slots;
setup currently has no equivalent retained inputs. Fresh replay and prefix
minimization must carry any added setup inputs together with their SQL.

Source and test files stay below 200 lines. Extract an existing responsibility
when needed; do not introduce an alternate recorder or duplicate SQLite syntax
and type semantics. Historical readers remain for frozen evidence.
