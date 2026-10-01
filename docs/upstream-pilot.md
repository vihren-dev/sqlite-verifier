# Runtime upstream mining (W6)

`just conformance-upstream` builds the pinned SQLite 3.51.0 Tcl testfixture and
runs the real harness over `alter*.test` and `e_*.test`. Tcl expands loops,
substitutions and capability guards. SQL is replayed through the pinned C library;
Tcl outcomes/results cross-check extraction, never supply the model oracle.

The review extraction scanned 45 files, executed 37, observed 21,546 assertions
and retained 341 cases with a cap of 20 per file. Eight files require fault,
corruption, authorizer or query-plan contexts. The complete per-instance reasons
and source hashes are retained in the compressed
[extraction manifest](../conformance/corpus-v3/extraction.json.gz).
Its digest is bound by [corpus v3](../conformance/corpus-v3/manifest.json).
The original 177-case `alter*` pilot remains immutable in v1.

A same-file close/reopen is a capture boundary backed by a real native connection
close: committed data survives and pending writes roll back. It no longer
poisons later assertions. Compatible DQS=1, DEFENSIVE=0 and TRUSTED_SCHEMA=1
configuration calls are replayed and read back. Other settings, connection open options and memory-database reopens remain excluded.
Native record version 2 represents these setup operations as `{"reopen":true}`
or `{"dbConfig":[option,value]}` among SQL strings; version 1 remains readable.
The SQL after the last connection boundary becomes the candidate migration.

ADR 0005's output acquisition is opt-in through `record_sql(..., outputs=True,
parameters=[...])`. Native record version 3 retains typed parameter slots,
column names/count (including empty results), rows, and the direct DML change
count. Supply one parameter tuple per statement; repeated named parameters share
SQLite's slot. SELECT, DDL and EXPLAIN have no change count. Native replay checks
these fields against a fresh execution. This acquisition version is distinct
from the Lean case format: admitted literal-write records map to case version two
and compare direct counts. Query and parameter semantics remain unsupported;
native acquisition records faithful tie groups and cutoff boundaries. Explicit
profile/clock evidence uses native version 4; see [profiles](execution-profile.md).
Default extraction continues to produce versions 1/2 unchanged.

ADR 0005 extraction preserves Tcl SQL call boundaries, including calls without
final semicolons. `onecolumn` and `exists` use SELECT-only native acquisition and
their own result semantics during the Tcl check; native rows stay unchanged.
Mixed helper calls compare independently. Pure eval row scripts return an empty
Tcl result while retaining ordinary native rows, including RETURNING. Accepted
bodies are empty or basic braced `expr` bodies without functions, command
substitution, namespace references or variable traces. Other bodies retain the
callback-context exclusion. The pinned harness check is
[upstream_helper_calls.test](../tests/upstream_helper_calls.test).

Second connections exclude assertions while open. After closure, a read-only
prefix may recover when it uses the same main database generation, keeps the
profile's settings unchanged, has no auxiliary read inside a primary transaction,
and reproduces every captured Tcl outcome/result on a fresh database. Auxiliary
writes, different databases and uncommitted reads remain excluded. Tcl string
equality alone cannot establish storage-class equivalence, so recovery requires
these conditions. Resetting the primary does not close auxiliary handles.
Connection command deletion traces capture real closure; renamed connection
commands retain an exclusion across resets because a renamed handle can survive.
The pinned harness check is
[upstream_context_calls.test](../tests/upstream_context_calls.test).

Attachment lifetimes come from SQLite's database inventory after each Tcl call.
After successful DETACH, the preceding SQL becomes a setup prefix and eligibility
returns only after fresh native replay verifies it. Setup may attach `:memory:`
databases and replay all their SQL before detaching; migration recording and
external-file attachment remain refused. A live attachment, failed DETACH or
unreplayable file prefix cannot recover. The pinned test is
[upstream_attachment_calls.test](../tests/upstream_attachment_calls.test).

Explicit-profile capture accepts `--profile PROFILE.json` and, for a controlled
clock profile, `--clock-unix-milliseconds VALUE`. The Tcl engine establishes and
reads back foreign-key and recursive-trigger settings. Its native clock hook
supports nonzero whole seconds through 2147483647; other values are refused.
Capture uses UTC and excludes tests that change the controlled clock. Native
recording retains outputs and the clock input for each reached statement, and
the manifest declares the profile. Fresh replay preserves that evidence.

The profile identifies the native recording engine. The Tcl testfixture has
additional test compile options; its source ID is checked, and the fidelity
check compares actual Tcl outcomes with native results. This does not measure
the gap to a workload's driver builds. Run `nix-build build-support/default.nix
-A tests.upstream --no-out-link` for the real profile capture check, including
defaults, triggers, cascading deletes and a rejected clock change.
Profile-setting refusals include the canonical PRAGMA name, so acquisition
reports count `foreign_keys` separately from `ignore_check_constraints` and other
settings. The pinned capture check exercises both names.

Removing the close exclusion does not by itself widen the supported execution
profile. `alter.test` still yields 12/119 and `alter3.test` 7/59: TEMP/ATTACH,
multiple connections and LEGACY_FILE_FORMAT=1 account for remaining exclusions.
Callbacks, ambiguous Tcl REAL/BLOB formatting and setup ending in a transaction
also remain excluded. External database access is denied before file creation;
nondeterministic functions are excluded rather than frozen as unstable truth.
Views, triggers, constraints and WITHOUT ROWID tables otherwise retain native
metadata and rows even when the model cannot represent them.

Native-only minimization tries at most 32 prefix deletions, preserving exact
initial state and trace. Every selected case must repeat exactly before capture.
Original prefixes and minimization counts remain in each record. Runtime-generated Tcl data may vary across extractions; frozen cases bind the actual expanded SQL, not just the source file. The source ZIP
and testfixture identities are checked, including SQLite's own manifest hashes.
Nearest EVIDENCE-OF blocks are attributed using runtime source frames, not every
requirement found anywhere in a file. Ambiguous blocks remain uncredited.

Refresh under `build/`, then create a new version without overwriting evidence:

```sh
python3 -m conformance.refresh_corpus --base conformance/corpus-v2 \
  --upstream build/upstream-pilot --output build/corpus-v3
```

V3 retains v2's exact records and adds 164 newly selected upstream cases plus 23
authored scenarios. `just conformance-corpus` replays fresh native observations;
`just conformance-progress` reports [versioned progress](conformance-progress.md).
The bounded frozen replay runs in `just test`; upstream re-extraction is an
explicit separate target. The three original static fixtures remain historical
regression evidence.
