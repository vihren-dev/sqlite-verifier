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
