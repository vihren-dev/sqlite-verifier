# ADR 0005 C4 fidelity triage

All 143 differing-result candidates in frozen v3's extraction have an identified
cause. The ADR's 123 headline counts prefix-result differences; the denominator
also contains 10 prefix-error outcomes, 5 assertion-error outcomes, 4 assertion
results and 1 assertion-error text difference. The
[summary](20261001-adr5-c4-fidelity.json) binds that historical extraction, the
[per-instance ledger](20261001-adr5-c4-causes.json.gz),
[original Tcl traces](20261001-adr5-c4-traces.json.gz),
[mechanical reproductions](20261001-adr5-c4-mechanical.json.gz), and
[binding experiment](20261001-adr5-c4-bindings.json.gz) by uncompressed SHA-256.

| Primary cause | Cases | Result |
| --- | ---: | --- |
| `PRAGMA database_list` observes database filenames | 95 | Paths differ; sequence/name cells match. Named environment mismatch; no path normalization |
| Tcl implicitly binds `$dots`; capture has no value/type | 14 | Named binding exclusion. Explicit typed native parameters remain available |
| Testfixture-only `PRAGMA lock_status` | 12 | Named build difference; no fabricated native lock rows |
| `db func` bypassed literal callback-method checks | 9 | Canonical method lookup now catches full names and unique abbreviations |
| Testfixture-only `echo` virtual-table module | 6 | Named missing-module difference; native oracle stays independent |
| Incremental BLOB mutation outside captured SQL | 4 | Connection/global BLOB operations now exclude their context until reset |
| Primary close/reopen lost its schema-cache boundary | 2 | C2 already preserves a real close/reopen; retained reproduction proves the difference |
| Newline joining merged separate Tcl SQL calls | 1 | C2 already preserves semicolon boundaries; retained reproduction proves the error text |

The 14 missing-binding cases also contain untraced BLOB writes. Historical raw
native execution stored NULL where Tcl bound forty dots. A separate native
experiment binds the actual TEXT through the typed C API: it restores the dots
before BLOB access, and still differs from Tcl's post-write value. The ledger
retains both causes. This experiment does not replace historical results or edit
native records. The four other BLOB cases have no implicit SQL parameter tokens.

The pinned `src/tclsqlite.c` method catalog resolves exact names and unique
prefixes through `Tcl_GetIndexFromObj`. The capture proxy now follows that rule
for helpers, callbacks and lifecycle calls. Canonical `collate` replaces the
incorrect `collation` spelling; callback contexts and nested SQL are refused.
Global `sqlite3_blob_*` calls are traced even outside an assertion, so an earlier
write cannot silently affect a later retained case. SQL lexical tokens detect
untraced named Tcl bindings in setup and candidate calls while ignoring quoted
identifiers, string literals and comments.

Named path, lock and module diagnostics are added only after an actual fidelity
mismatch. Internal attachment inventory still uses `database_list`. The pinned
`src/pragma.c` implements `lock_status` only under `SQLITE_DEBUG` or `SQLITE_TEST`;
the production native build does not supply that testfixture feature.

Frozen corpus artifacts and the historical extraction remain unchanged. C6's
new extraction must triage any newly observed differing candidates before freeze.

Verification: full hermetic model/corpus suite, 112 passed in 131.86 seconds;
pinned upstream capture suite, 7 passed in 0.57 seconds; focused fidelity,
ordering and upstream regressions, 32 passed in 5.68 seconds. Documentation links
pass. The ledger test checks exact historical keys, cause totals and all evidence
digests; the independent final audit found no actionable gaps.
