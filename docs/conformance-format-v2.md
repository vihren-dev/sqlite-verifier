# Conformance outputs and native acquisition

ADR 0005 adds statement outputs and typed parameters to the
[conformance case](conformance-format-v1.md). This is the comparison interface for
the literal-write subset. Native acquisition supports ordered queries and explicit
profiles; missing model capabilities remain unsupported.

A case whose record has outputs carries them in two fields; a case without them
has `outputs: null` and `parameters: []`:

- `parameters`: one array of typed values per reached statement, using the shared
  value codec. The model runs each statement with the values of its array bound
  to its parameters; a statement without an array binds no values.
- `outputs`: one object per reached statement, with `result` and `groups`.
  `result` has `columns` (ordered names), `rows` (arrays of typed values), and
  `changes` (a nonnegative direct DML count or null for other statements).
  Column shape is present even when `rows` is empty.

`groups: null` compares rows as a multiset. An array describes ordered native tie
groups: each has `rows` (the complete eligible multiset) and `count` (the number
selected by the window). Each row occurrence is consumed once; groups keep their
order. A boundary group may select fewer rows than it contains. The decoder
checks row widths, counts, and that native rows satisfy their own group evidence.
Stored groups select at least one row; only the first and last may be partial.
Both arrays have one fewer entry than `nativeTrace`, which includes initialization.

`classifyCase` compares stored state through the existing production trace, then
compares statement outputs. Output instrumentation follows production `advance`:
INSERT counts one per VALUES row on success; UPDATE counts the rows that its
filter selects, including unchanged values; supported ABORT constraint failures
count zero. Other DML failures have
no modeled output capability and stay unsupported. No query evaluator is added.

The acquisition format has a separate version: `nativeVersion: 3` records typed
parameters, `columns`, `columnCount`, `rows`, and `changes` beside each native
statement observation. Fresh native replay binds the recorded parameters and
checks outputs and state. The adapter validates acquisition fields before
the statement mapping and builds a case with outputs from each admitted record. Ordered query
records cannot yet reach model comparison because query semantics are absent;
faithful tie-group acquisition is required before those cases can be frozen.

Supplementary probes use a native SELECT-only authorizer before preparation,
plus SQLite's read-only and EXPLAIN flags before stepping. They reject PRAGMAs,
transaction control, DDL, DML and nondeterministic random functions. The guard
delegates to the acquisition authorizer and restores it after success or failure.

[Native tie grouping](../conformance/native_ordering.py) accepts engine-ordered
full rows and resolved projected keys with built-in collations. The recorder
resolves projected names, ordinals and unchanged qualified columns, and ranks an
uncut query through an outer SELECT. DISTINCT, GROUP BY and compound results stay
inside the original query. SQLite supplies comparison semantics, including
inherited collations, numeric ties, direction and NULL placement. Window
intersection retains both complete boundary groups, including one group cut at
both ends. Probes preserve parameter slots and must reproduce the original rows
and shape. Hidden or ambiguous keys are excluded as "tie structure not observable".
Limited INSERT sources are probed before writing; a partial group is excluded as
"unspecified choice inside a write". A unique-key cut can execute, and the write
itself runs once. Nested windows and other unresolved limited-write contexts are
excluded as "tie structure not observable".

Explicit profiles use acquisition `nativeVersion: 4`, retaining v3 output fields
and adding a `profile` record and `setupClockUnixMilliseconds`. Controlled-clock
profiles add `clockUnixMilliseconds` to each reached statement. Native replay
validates the profile and supplies those clock values through a private native
VFS, including default/trigger reads and supplementary probes. Different profile
identities, engine builds, transaction modes and changes to established behavioral
settings during case SQL are refused. Setup can replay FK changes when it restores
the selected profile before case SQL. Transaction-local FK writes keep SQLite's
no-op behavior; readback still checks the fixed profile after each statement.
The model implements a profile when it uses SQLite's default execution settings: no
foreign keys or recursive triggers, DEFERRED transactions, no controlled clock,
read-write access, trusted schema mode and no other writers
(`conformance/profile_scope.py`). Name resolution then uses the profile's release,
build, limits and double-quoted-string settings. A record whose profile changes
another setting is `MODEL_UNSUPPORTED`, with the setting named; malformed evidence is
a harness error.
A profile record of format 3 also has `limits`, the measured connection limits
([execution profile](execution-profile.md)); replay establishes and reads them back.
Records of formats 1 and 2 have the limits of their compile options.
Acquisition `nativeVersion: 5` is version 4 with a profile of format 3 and a `phase`
in each trace event: `prepare` when `sqlite3_prepare_v2` failed, `step` when
`sqlite3_step` failed, and `null` otherwise. `conformance/record_versions.py` lists
what each version carries. No frozen record has version 5 yet.
Acquisition `nativeVersion: 6` is version 5 from a recorder that runs on after an
SQL error, so each statement of the migration has one event, also after a failed one.
The case of such a record has `continues: true`, and `classifyCase` compares it with the
model's run that continues after an error (`runPassFrom`): each statement resolves
against the state of the connection when it runs. The prediction of such a record comes
from the same run. Every other case has `continues: false` and keeps the pass that stops
at the first error.
Manifests declare `executionProfiles`, an array of these complete profile records.
Every v4 record must match a declaration exactly; duplicate name/version identities
and missing or conflicting declarations are refused. Legacy corpora retain their
implicit profile. External workload commands remain work in progress.

New acquisition uses Tcl display policy version 2. It establishes precision zero
after `tester.tcl`, then retains source-owned precision changes observed at each
successful SQL call. A REAL display must parse to the exact independently
recorded IEEE bits, including signed zero. Rounded collisions and unobservable
precision stay refused. Policy version 1 retains its zero-only requirement when
historical evidence is read. Native REAL cells are never replaced with display text.

Binding recording has an independent `bindingRecordingVersion: 1`. Native
acquisition versions 3 and 4 keep their existing output and profile meanings.
`bindingRecordingKind` distinguishes `tcl` source observations from `explicit`
typed setup inputs. Each `setupBindings` entry corresponds to one
`setupCommands` entry and contains the reached statement vectors
`{parameterNames, parameters}`. Connection controls have an empty vector list.
Trace events retain `parameterNames` beside the existing typed `parameters`.
SQLite supplies the slot names and count before stepping; repeated names share
one slot. Explicit inputs can use anonymous slots, numbered slots and NULL.
Tcl inputs require an independently observed value for every actual named slot.
Missing values, unnamed slots, surplus evidence and bound prepare errors are
refused. Comments and quoted SQL text cannot supply parameter slots.

Tcl recording retains `sourceCalls`: version 1, original `setup` and `assertion`
call arrays. Each call retains SQL, helper, return code, expected result strings,
precision, NULL display marker, typed bindings and Tcl object metadata. Original
connection controls have null call entries and remain in `sourceSetupCommands`.
`setupCallIndices` selects the current setup from that original evidence. Prefix
minimization removes setup SQL, vectors, helpers and indices together; it never
changes the original calls. Both recording kinds retain `setupHelpers`,
`migrationReadonly`, `migrationReadonlySpans` and `auxiliaryReplay` for fresh
replay. The complete validation (`conformance.corpus.validated_load`) checks
this extension before model admission. A frozen corpus gets this validation
once; [Continuous integration](ci.md) describes the locked frozen corpora.
Fresh replay checks actual slot names, bound values, source expectations and
native observations. Historical records retain their original replay shape.

New Tcl acquisition reports use report `corpusVersion: 2` and `tclBindingPolicy`
version 1. Each accepted instance and its upstream record retain
`tclCallsSha256`, the SHA-256 digest of canonical `sourceCalls` JSON. Frozen
manifests bind the report policy and original source-call evidence. Historical
report version 1 retains its refusal of uncaptured named bindings; relabeling
new evidence or removing its recording extension cannot bypass that refusal.

The Tcl observer preserves the original scalar object and its string-representation
state. Named source bindings refuse variable traces, source execution callbacks,
array forms, mixed `@` conversions and row-script contexts. Typed TEXT and BLOB
binding bytes remain exact, including Tcl's encoded NUL and CESU-8. Native replay
can retain and compare their storage class and hexadecimal bytes. Direct TEXT
displays that the current UTF-8 comparator cannot decode retain a named refusal
with the source instance. Source SQL whose Tcl bytes differ from the UTF-8 event
transport is also refused, even when its result would hide that difference. The
recorder does not replace or normalize those bytes.

Native corpus storage has its own `snapshotStorageVersion: 1`, independent of
`nativeVersion`. A record's `snapshots` object maps SHA-256 digests to complete
`{schema, tables}` snapshots. Each initial/trace `visible` and `persisted` field
contains `{"snapshot": "DIGEST"}`. Digests use canonical UTF-8 JSON with sorted
keys, compact separators and unescaped non-ASCII characters. Corpus loading checks
the manifest's stored-byte digest, verifies every snapshot and reference, and
restores independent observations before replay or model translation. Unknown
storage versions, missing references, altered digests and unused pool entries
are refused. Legacy unshared records retain their original meaning and size policy.
