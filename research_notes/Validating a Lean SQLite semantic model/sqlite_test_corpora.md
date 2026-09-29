# SQLite test corpora and extraction techniques for validating a Lean 4 SQLite model

Method note: numbers marked **[verified-local]** were computed by the researcher on 2026-09-29 by cloning `github.com/sqlite/sqlite` (trunk commit `1059bc8eace8`, committed 2026-09-28; tag `version-3.51.0` was also fetched), `github.com/gregrahn/sqllogictest` (SLT mirror, last commit 2026-04-15), `github.com/tursodatabase/turso` (main, 2026-09-29) and `github.com/duckdb/duckdb`, then running `grep`/`wc`/`sqlite3` over them. They are grep counts of *call sites at line start*. They are not counts of executed tests, because `foreach` loops multiply tests and some call sites span lines. The source for these is the corresponding GitHub repo. Numbers marked **[estimate]** are the researcher's own inference.

## 1. The SQLite Tcl test suite (test/*.test): size, structure, composition

### Takeaway
There are about 1,195 `.test` files on trunk (1,174 at `version-3.51.0`), about 488k lines, and about 47k test call sites (sqlite.org says 51,445 distinct cases). Everything is built on `do_test` plus thin wrappers (`do_execsql_test`, `do_catchsql_test`). The DDL/DML-relevant subset (about 77 files) has about 4.2k call sites. Roughly 30% of files look "pure SQL" by a crude heuristic, and those files hold about 7.6k `do_execsql_test`/`do_catchsql_test` sites.

### Cited Findings
- sqlite.org's own figures for the Tcl harness: "1390 files totaling 23.2MB", "51445 distinct test cases", "millions of separate tests" with parameterization, and 27.2 KSLOC of C harness code. The 1390-file figure includes non-`.test` files such as helpers, `.db`, and `.c`. The same page gives SLT as 7.2M queries / 1.12GB, TH3 as 50,362 distinct cases / 2.4M instances, and dbsqlfuzz as about 1 billion mutations per day with 336 seed files. — [How SQLite Is Tested](https://www.sqlite.org/testing.html)
- **[verified-local]** Trunk `test/` holds 1,195 `*.test` files (1,290 entries in total) and 487,843 lines of `.test`. Tag `version-3.51.0` has 1,174 `*.test` files. `altercons*.test` exists on trunk but **not** at 3.51.0, which suggests post-3.51 ALTER work. Pin extraction to the 3.51.0 tag. — [sqlite/sqlite GitHub mirror](https://github.com/sqlite/sqlite)
- **[verified-local]** Line-start call-site counts on trunk:
  - `do_test` 31,133 in 877 files
  - `do_execsql_test` 14,252 in 715 files
  - `do_catchsql_test` 1,463 in 252 files
  - `do_eqp_test` 410 in 78 files
  - `do_faultsim_test` 297 in 74 files
  - `do_malloc_test` 144 in 34 files
  - `do_expr_test` 98
  - `do_select_tests` 66 (3 files)
  - `do_createtable_tests` 66 (1 file, e_createtable)
  - `do_ioerr_test` 47
  - `do_multiclient_test` 43
  - `do_update_tests` 19, `do_delete_tests` 18, `do_insert_tests` 12

  Also, 389 files contain `foreach` loops, 774 files use `ifcapable`, and 161 mention `EXPLAIN`/`do_eqp_test`. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)
- **[verified-local]** Harness semantics, from `test/tester.tcl` (2,626 lines):
  - `do_execsql_test ?-db DB? name sql ?result?` expands to `do_test name "execsql {sql} db" [list {*}$result]`.
  - `do_catchsql_test name sql result` expands to `do_test name "catchsql {sql}" result`.
  - `execsql` is just `$db eval $sql`.
  - `catchsql` returns the Tcl list `{rc msg}`: `{0 {rows...}}` or `{1 {error message text}}`.
  - `do_test` accepts `/regex/`, `~/regex/`, and `#/…/` numeric-within-10% expected forms.
  - `ifcapable EXPR code ?else code?` evaluates against `$::sqlite_options(...)`.
  - `reset_db` closes the connection and deletes `test.db`.
  - `finish_test` ends the file.
  - An `execpresql` hook (`::G(perm:presql)`) runs permutation-specific SQL on each new handle.

  — [tester.tcl](https://github.com/sqlite/sqlite/blob/master/test/tester.tcl)
- **[verified-local]** Tests run under `testfixture`, a tclsh with SQLite and many C test commands (`sqlite3_*`, `testvfs`, `hexio_*`) statically linked in. `test/testrunner.tcl` runs files in parallel and is invoked by `make devtest`/`make releasetest`. See `doc/testrunner.md` and `doc/tcl-extension-testing.md` in the source tree. — [doc/testrunner.md](https://sqlite.org/src/doc/trunk/doc/testrunner.md); [tcl-extension-testing.md](https://sqlite.org/src/doc/trunk/doc/tcl-extension-testing.md)
- **[verified-local]** Crude "pure SQL" heuristic: a file is excluded if it mentions any of faultsim, malloc/ioerr tests, testvfs, `sqlite3_*` C-API commands, multiclient, crashsql, `db_save`, `hexio_`, `incrblob`, `db close`, a second connection, `wal_`, FTS/rtree, or `do_eqp_test`. By that rule, 361 of 1,195 files (30%) are clean, and they contain 7,643 `do_execsql_test`+`do_catchsql_test` sites. The rule is conservative, since `db close`/reopen alone excludes many useful files. Separately, 8,734 `do_test` bodies begin with a bare `execsql`/`catchsql` on the next line. These are candidates for the simple-shape extractor. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)
- **[verified-local]** Filename families by prefix count: fts 95, tkt 83+36 (ticket regressions), e_ 25, vtab 12, json 11, window/wal/trigger/shell/select/orderby/fkey/collate 9 each, index/join/where/rowvalue/misc/func/crash/corrupt 8 each, without_rowid 7, malloc 7, savepoint 5, pragma 5, upsert 5, insert 4, delete 4. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)
- **[verified-local]** Per-file call sites for the user's scope. The format is `do_test/do_execsql_test/do_catchsql_test`, followed by the number of distinct R-ids cited.
  - **ALTER**
    - alter.test 97/13/5
    - alter2 46/0/0 (legacy file-format tricks, hexio)
    - alter3 47/2/10
    - alter4 45/6/3
    - altertab 3/113/21
    - altertab2 0/34/3
    - altertab3 2/86/18
    - altercol 0/99/21
    - alterdropcol 0/37/18
    - alterdropcol2 0/6/3 (10 R-ids)
    - also alterlegacy, altertrig, alterqf, alterauth*, altermalloc*, alterfault, altercorrupt
  - **Evidence (e_) files**
    - e_createtable 8/65/23 (70 R-ids; plus 66 `do_createtable_tests` blocks, each holding many sub-cases)
    - e_insert 1/4/4 (18)
    - e_update 1/17/1 (23)
    - e_delete 1/8/0 (19)
    - e_select 8/45/7 (96)
    - e_select2 0/2/0 (7)
    - e_expr 28/245/12 (108)
    - e_fkey 266/0/0 (97)
    - e_droptrigger 10/0/0
    - e_dropview 12/15/7
    - e_reindex 0/22/0
    - e_resolve 0/18/11
    - e_changes 6/18/2
  - **Transactions and savepoints**
    - trans 131/0/0
    - trans2 11, trans3 8
    - savepoint 121/2/0
    - savepoint2/4/5/6: 7/6/3/5
  - **Types and affinity**
    - types 28, types2 4, types3 14/5
    - affinity2 0/25, affinity3 0/16
  - **Rowid, autoincrement, constraints**
    - rowid 135/21/6
    - autoinc 84/4/0
    - conflict 72/5/4, conflict2 72/2/0, conflict3 1/58/12
    - unique 35, unique2 4/0/2
    - notnull 69/1/0, notnull2 0/8
    - check 69/28/9
    - default 5/17/6
  - **Indexes**
    - index 102/3/0, index2 7, index3 4/6, index4 0/9/1, index5 3, index6 20/52, index7 21/21/1
  - **DML**
    - insert 53/16/7, insert2 25/4, insert3 18, insert4 52/6/3, insert5 12/1
    - update 123/14/1, update2 1/26
    - delete 55/6, delete2 9, delete3 2
  - **Other**
    - table 82/5/6
    - without_rowid1 1/51/8
    - upsert1 0/24/11
    - cast 87/42/0
    - expr 29/15/1
    - coalesce 9

  There are no `drop.test` or `droptrigger.test` files. DROP TABLE is covered inside table.test, e_droptrigger, and others. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)
- **[verified-local]** Across 77 DDL/DML/transaction/constraint/index/type/expression files (the list above plus fkey1/2, schema/schema2, alterlegacy, altertrig, alterqf), the static totals are 2,574 `do_test` + 1,425 `do_execsql_test` + 261 `do_catchsql_test`, or about 4,260 call sites. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)
- **[verified-local]** Distinct `R-nnnnn-nnnnn` IDs cited anywhere in `test/*.test`: 781, across 65 files. In `e_*.test` alone: 601. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)

### Inferences
- Older files (alter.test, trans.test, index.test, conflict.test, rowid.test, notnull.test, unique.test) are dominated by `do_test {…} {execsql {…}} {…}` bodies. Newer files (altertab*, altercol, alterdropcol, conflict3, affinity2/3, without_rowid1, upsert1) use `do_execsql_test`/`do_catchsql_test` almost exclusively. The newer files are the cheapest targets for the next scope: rebuild/rename/drop-column plus constraints.
- **[estimate]** With loops and `do_createtable_tests`/`do_select_tests` sub-cases expanded, the relevant 77 files probably execute about 5k–8k assertions. Test-count summaries from an actual testfixture run would give the exact number.
- alter2.test and alter4.test lean on file-format and legacy tricks (`PRAGMA legacy_file_format`, hexio writes, temp tables). Expect a lower yield of pure-SQL cases there.

### Gaps
- An exact executed-test count per file under a 3.51.0 default build was not measured, because testfixture was not built. `testrunner.tcl` output ("N errors out of M tests") would supply it.
- The pure-SQL fraction is a grep heuristic, not a semantic classification.

## 2. Practical extraction: instrument the harness rather than parse Tcl

### Takeaway
The robust route is dynamic. Run the real `.test` files under testfixture (or a tclsh with the sqlite3 package) with a shim that:
- wraps each connection command to log every `eval`/`onecolumn`/`exists` SQL, its typed result or error code+message, and the connection name;
- redefines `do_test`/`do_execsql_test`/`do_catchsql_test` to emit test-boundary markers and the expected value.

Each case then becomes "all logged statements since the last DB reset + the assertion's SQL". Minimize that by replaying natively. Turso already does the connection-replacement trick, by implementing the `sqlite3` Tcl command over its own engine, and also ships a best-effort static Tcl-to-`.sqltest` converter.

### Cited Findings
- **[verified-local]** `tclsqlite.c` exposes these connection subcommands: `trace`, `trace_v2` (event mask includes `statement`, `profile`, `row`, `close`), `profile`, `nullvalue`, `errorcode`, `erroroffset`, `onecolumn`, `exists`, `eval ?options?`, `serialize`, `deserialize`, `total_changes`, `last_insert_rowid`, `update_hook`, `rollback_hook`, `wal_hook`, `preupdate_hook`. So statement-level tracing is available without C changes (`db trace_v2 {callback} statement`). — [src/tclsqlite.c](https://github.com/sqlite/sqlite/blob/master/src/tclsqlite.c); [Tcl interface docs](https://sqlite.org/tclsqlite.html)
- **[verified-local]** `execsql` returns `$db eval $sql`, which is a *flat Tcl list* of all result cells from all statements in the script. NULL renders as the `nullvalue` string (empty by default). Integer 1, real 1.0 (rendered via Tcl), and text '1' are not distinguished in the expected list. `catchsql` returns only `{1 msg}`, with message text and no error code. — [tester.tcl](https://github.com/sqlite/sqlite/blob/master/test/tester.tcl)
- **[verified-local]** Turso runs the *upstream SQLite Tcl files* against its engine:
  - `sqlite/conformance/upstream/` holds 846 vendored `.test` files plus copies of `tester.tcl`, `malloc_common.tcl`, `wal_common.tcl`, and others.
  - `bindings/tcl/turso_tcl.c` is described in its Makefile as a "Tcl command compatible with the upstream SQLite Tcl binding, enabling the sqlite/conformance/upstream harness to run without a subprocess per statement".
  - `run_file.tcl` wraps each file so that a top-level Tcl error becomes a `FILE-ABORTED` failure instead of silently counting zero tests.

  — [tursodatabase/turso](https://github.com/tursodatabase/turso) (paths `sqlite/conformance/upstream/`, `bindings/tcl/`)
- **[verified-local]** Turso's `testing/sqltest/src/tcl_converter/{mod.rs,parser.rs,utils.rs}` is an "error-recoverable parser that converts the legacy Tcl-based test format to the new `.sqltest` DSL format". Turso's testing skill says: run `cargo run -- convert <TCL_test_path> -o <out_dir>`. It "is not always accurate… If some conversion emits a warning you will have to write by hand whatever is missing from it (e.g unroll a for each loop by hand)". — [turso tcl_converter](https://github.com/tursodatabase/turso/tree/main/testing/sqltest/src/tcl_converter); [Turso testing skill](https://smithery.ai/skills/tursodatabase/testing)
- **[verified-local]** Turso's converted/hand-written corpus is `sqlite/conformance/sqlite-sqltests/`: 348 `.sqltest` files with 9,302 `test` blocks. There are also 71 files in `turso-sqltests/`. `alter_table.sqltest` alone has 223 tests. The format is `@database :memory:`, then `test name { SQL… } expect { rows as a|b }`, plus `expect error {regex}`, named `setup` blocks, `@skip`, `@cross-check-integrity`, and snapshot tests for EXPLAIN. Every test gets a fresh DB ("Parallel-safe: All tests are isolated"). — [turso dsl-spec.md](https://github.com/tursodatabase/turso/blob/main/testing/sqltest/docs/dsl-spec.md); [Turso COMPAT.md](https://github.com/tursodatabase/turso/blob/main/COMPAT.md)
- A Turso search summary reports that "TCL tests are being phased out in favor of the .sqltest suites in sqlite/conformance/". Compatibility is validated through differential testing against SQLite and "ongoing work to pass the full SQLite TCL test suite". — [Turso simulator README](https://github.com/tursodatabase/turso/blob/main/testing/simulator/README.md); [Turso GitHub issue #1710 on tester.tcl differences](https://github.com/tursodatabase/turso/issues/1710)
- No public project was found that dumps SQLite's Tcl tests to JSON as (setup, query, typed expected) triples. Searches returned only general harness descriptions. — [search results, e.g. code-maven Testing SQLite](https://code-maven.com/testing-sqlite)

### Inferences
Recommended instrumentation design, by the researcher (not a published tool):
1. Source a `shim.tcl` after `tester.tcl`, or preload it via the permutation mechanism.
2. `rename sqlite3 ::real_sqlite3`, then define `proc sqlite3 {name args}`. It creates the real handle under a hidden name and a proxy command `name` that logs:
   - for `eval`/`onecolumn`/`exists`: `{conn, sql, ok|err, errcode ([$h errorcode]), msg, rows-with-types}`. Types come from `eval` with an array var, or better from re-running natively later.
   - for `close`: a close marker.
3. Redefine `do_test` to emit `BEGIN_TEST name` / `END_TEST name expected actual pass`, then call the original. The wrappers funnel into `do_test` automatically, so only `do_test` needs overriding (plus `do_eqp_test` for exclusion).
4. Treat `reset_db`, `forcedelete test.db`, `db close` + `sqlite3 db test.db`, `do_not_use_codec`, and `ATTACH` as segmentation or complication events.
5. Emit JSONL. Also log `db trace_v2 … statement` to catch SQL issued inside Tcl helper procs.

This approach handles `foreach` loops, `ifcapable`, string substitution (`$::var` inside SQL), and helper procs for free, because it observes what actually ran on the 3.51.0 build.

Segmentation into self-contained cases:
- Each assertion's setup = the ordered list of successful *and failed* statements on `db` since the last reset. Failed statements matter because they can have partial effects inside transactions.
- Then delta-minimize by replaying with the native pinned runner: drop statements while the assertion result stays identical. This mechanically turns "shared DB per file" into independent cases.
- Cases that touch a second connection (`db2`), file bytes, `db close`/reopen of a persistent file, or Tcl-registered user functions (`db func`) should be tagged and excluded.

Expected values:
- Do *not* use the Tcl expected lists as ground truth for typed proofs, since they are flat, untyped, and lose NULLs.
- Use them only as a pass/fail oracle. Record the canonical expectation by re-running the minimized case natively with typed output, e.g. `SELECT typeof(x), quote(x)` or the C API column types, and with `sqlite3_extended_errcode` for errors.

This matches the user's existing "native runner reproduces Tcl connection config" design. Additional connection flags to reproduce:
- `SQLITE_DBCONFIG_DEFENSIVE` off and trusted_schema on (the user already does this);
- `sqlite_options` feature set;
- `PRAGMA` defaults that tests set explicitly.

Static extraction (the user's current approach, and Turso's converter) is complementary. It preserves the author's intent and test names, but coverage caps out: Turso's converter needs manual unrolling of loops.

### Gaps
- Whether stock macOS `/usr/bin/tclsh` plus `package require sqlite3` can source `tester.tcl` without testfixture-only commands (e.g. `sqlite3_memdebug_settitle` is called in `do_test`) was not tested. Stubbing those procs is likely needed. **[estimate]**
- Turso's current pass rate on the upstream Tcl files was not found in a citable form.

## 3. Requirement IDs (R-nnnnn-nnnnn), evidence marks, and machine-readable requirement lists

### Takeaway
Requirements are sentences in the HTML docs marked with `^…` or `^(…)^` in docsrc. Their IDs are `R-` + an MD5-derived hash of the normalized text (`md5-10x8`). `matrix.tcl` extracts them into a SQLite db (`docinfo.db`, tables `requirement`, `reqsrc`, `evidence`, plus `history.db` `allreq`). `scan_test_cases.tcl` scans C, Tcl, SQL, SLT and TH3 sources for `EVIDENCE-OF:`/`IMPLEMENTATION-OF:` comments. The published matrix lists 3,487 requirements, of which 65.7% have any evidence and only 24.9% have public Tcl evidence (870). Most of the rest are covered only by the proprietary TH3.

### Cited Findings
- `docsrc/matrix.tcl` "generates the requirements traceability matrix". It scans `doc/*.html`, `doc/c3ref/*.html` and `doc/syntax/*.html`. "Requirements text is text between "^" and "." or between "^(" and ")^"", normalized by stripping HTML and collapsing whitespace. `set reqno R-[md5-10x8 $req]`. Rows go to `requirement(reqno, reqtext, origtext, reqimage, srcfile, srcseq)`, `reqsrc`, and `history.allreq`. It reports "stale evidence" for IDs cited in tests but no longer in docs. — [docsrc matrix.tcl](https://www.sqlite.org/docsrc/file/matrix.tcl)
- `docsrc/scan_test_cases.tcl` scans for `EV:`, `EVIDENCE-OF:`, `IMP:`, `IMPLEMENTATION:` and `ANALYSIS-OF:` followed by a full `R-00000-…` number (8 groups) or a prefix ("usually the first two 5-digit groups suffice"), optionally with the text, which is verified. `-- comment` after the number marks the rest as a non-requirement comment. — [docsrc scan_test_cases.tcl](https://www.sqlite.org/docsrc/file/scan_test_cases.tcl)
- The docsrc build expects `../sqlite`, optionally `../th3` and `../sqllogictest`: "The TH3 and SQL Logic Test installs are optional and are only used for requirements test coverage tracking". The docsrc tree also has `req`/`requirements` entries and `format_evidence.tcl`. — [docsrc README](https://sqlite.org/docsrc/doc/trunk/README.md); [docsrc file list](https://www.sqlite.org/docsrc/dir?ci=tip)
- The published matrix has per-document summary and details pages (`matrix/matrix_s<doc>.html`, `matrix/matrix_d<doc>.html`) with columns tcl/slt/th3/src/any. Overall coverage: tcl 24.9%, slt 1.5%, th3 47.6%, src 5.8%, any 65.7%. **[verified-local]** Summing the per-document rows gives 3,487 requirements in total (tcl 870, slt 52, th3 1,660, any 2,291), consistent with the percentages. `www.sqlite.org/matrix/matrix.html` returned 404. The copy on `www2.sqlite.org`, and draft copies, are live. — [Requirement matrix](https://www2.sqlite.org/matrix/matrix.html); [lang_createtable details](https://www2.sqlite.org/matrix/matrix_dlang_createtable.html)
- Per-document (tcl/slt/th3/any out of total):
  - lang_createtable 67/0/3/71 of 74
  - lang_altertable 9/0/19/20 of 21
  - lang_insert 17/0/0/17 of 17
  - lang_update 23/8/0/23 of 23
  - lang_delete 19/0/0/19 of 25
  - lang_expr 112/4/32/136 of 158
  - datatype3 0/0/99/99 of 99 (type affinity is Tcl-untraced)
  - lang_transaction 0/0/0/0 of 27
  - lang_select 105/0/12/114 of 119
  - lang_droptable 0/2/8/9 of 9
  - lang_createindex 0/0/14/14 of 17
  - foreignkeys 97/0/98/98 of 98

  — [Requirement matrix](https://www2.sqlite.org/matrix/matrix.html)
- Example requirement: R-17899-04554 "It is an error to attempt to create a table with a name that starts with 'sqlite_'", with evidence tcl, slt, th3, src. — [lang_createtable details](https://www2.sqlite.org/matrix/matrix_dlang_createtable.html)
- **[verified-local]** SLT's `test/evidence/` files cite R-ids too, e.g. slt_lang_update.test has 23 `EVIDENCE-OF`/`TBD-EVIDENCE-OF` comments, slt_lang_createtrigger 33, slt_lang_aggfunc 25. — [sqllogictest mirror](https://github.com/gregrahn/sqllogictest/tree/master/test/evidence)

### Inferences
- The machine-readable requirement list is not published as a file. You regenerate it by checking out docsrc (Fossil) at the release matching 3.51.0 and running `matrix.tcl`, which requires building the docs first. Alternatively, scrape `matrix_d*.html` pages. There are about 211 document detail pages linked from the index.
- Requirement coverage by *public* tests is thin exactly where a migration verifier cares: datatype3 (type affinity, 99 reqs), lang_transaction (27), lang_createindex (17), lang_droptable (9), and lang_altertable (only 9/21 have Tcl evidence). The model team would have to write their own cases for these and tag them with R-ids. The matrix gives the exact sentence list to target.
- Because the ID is an MD5 of the normalized text, the IDs are stable across doc versions as long as the sentence is unchanged. The user can compute IDs for 3.51.0 docs themselves with the same normalization.

### Gaps
- `md5-10x8` is a docsrc Tcl helper whose exact definition (which digits, how grouped) was not read.
- The date and version of the live matrix pages are not shown on the pages.

## 4. sqllogictest (SLT)

### Takeaway
SLT has 622 files, about 7.2M `query` records and about 225k `statement` records, in 1.1 GB. Almost all of it is machine-generated SELECT/expression/aggregate/index/view workloads over tiny integer tables. About 13.5% of queries have hash-only expected results. Engine-neutral and deterministic-by-design, it is a good bulk source for *expression/SELECT* semantics but nearly useless for DDL/ALTER/transactions. Its `evidence/` directory (12 files, 318 queries) is the only SQLite-requirement-tagged part.

### Cited Findings
- Format:
  - `statement ok` / `statement error` (no error text).
  - `query <types> <sort> <label>`, where types are T/I/R and sort is `nosort` (default), `rowsort`, or `valuesort`.
  - Rendering: integers `%d`, reals `%.3f`, NULL as `NULL`, empty string as `(empty)`, control chars as `@`.
  - `hash-threshold N`: results above N values are stored as "N values hashing to <md5>". 10–20 is recommended.
  - `skipif`/`onlyif <engine>` and `halt`.

  Stated scope is "does the database engine compute the correct answer". Explicitly **not** tested: transactions, concurrency, performance. No Unicode. Engines compared: SQLite, MySQL, PostgreSQL, Oracle, MS-SQL, and others. — [SLT about.wiki](https://www.sqlite.org/sqllogictest/doc/trunk/about.wiki)
- **[verified-local]** Corpus composition (gregrahn mirror, 2026-04-15):
  - `test/select1-5.test`: 8,884 queries.
  - `test/random/{aggregates,expr,groupby,select}`: 391 files, 5,290,559 queries, 4,692 statements, 191,962 hashed.
  - `test/index/{between,commute,delete,in,orderby,orderby_nosort,random,view}/{1,10,100,1000,10000}`: 214 files, 1,895,581 queries, 218,681 statements, 773,940 hashed.
  - `test/evidence`: 12 files, 318 queries, 176 statements, 30 `statement error`, 0 hashed. The files are in1, in2, slt_lang_aggfunc, createtrigger, createview, dropindex, droptable, droptrigger, dropview, reindex, replace, update.
  - Totals: 7,195,342 queries, 225,371 statements, 973,295 hashed results.
  - The most common directives are MySQL/PostgreSQL skips (`skipif mysql # not compatible` 1.47M).

  — [gregrahn/sqllogictest](https://github.com/gregrahn/sqllogictest); [official Fossil SLT](https://www.sqlite.org/sqllogictest)
- A Git mirror updated weekly by GitHub Actions also exists: jzombie/sqlite-sqllogictest-corpus. — [sqlite-sqllogictest-corpus docs](https://docs.sqlite-sqllogictest-corpus.zenosmosis.com/)
- sqllogictest-rs (Rust) extends the format:
  - `statement|query error <regex>` and SQLSTATE matching;
  - `<slt:ignore>`, `system ok`, `retry`, `let`, variable substitution;
  - `--override` to rewrite expected output from actual output.

  Its users are RisingLight, RisingWave, DataFusion, Databend and CnosDB. Its README does not mention hash-threshold. — [sqllogictest-rs](https://github.com/risinglightdb/sqllogictest-rs)
- DuckDB uses "an extended version of the SQL logic test suite, adopted from SQLite" (`require`, `__TEST_DIR__`, `.test_slow`, `PRAGMA enable_verification`). **[verified-local]** Its repo keeps a C++ SLT runner plus only `select1-4.test_slow` from SQLite under `test/sqlite/` (25 files in total there). Its own tests live under `test/sql`. — [DuckDB sqllogictest intro](https://duckdb.org/docs/lts/dev/sqllogictest/intro); [duckdb/duckdb test/sqlite](https://github.com/duckdb/duckdb/tree/main/test/sqlite)
- Apache Calcite's hydromatic/sql-logic-test packages SLT for Java. — [hydromatic/sql-logic-test](https://github.com/hydromatic/sql-logic-test)

### Inferences
- The SLT shape (setup statements, then a query, then expected rows) matches the user's case format directly. But:
  1. Expected values are type-coerced strings (I/R/T via printf), so typed expectations must be regenerated natively. Hashed ones in particular must be recomputed as explicit values by running pinned sqlite3.
  2. `rowsort`/`valuesort` mean the model's check must compare multisets, not sequences.
  3. Each file shares state across hundreds of queries. The setup is usually a fixed prefix of CREATE/INSERT, which makes segmentation easy.
  4. Many random/index files are extremely redundant, e.g. the same query over 10/100/1000/10000 rows. For Lean proofs by `decide`/evaluation, the 10-row variants are the practical ones.
- Best SLT use for the roadmap: the expression-evaluation and SELECT phase. Sample, dedupe by query-shape, and keep the smallest table sizes. For DDL/rebuild/constraint semantics, SLT offers only `evidence/` (≈500 records).

### Gaps
- sqllogictest-rs support for `hash-threshold` was not confirmed.
- The official Fossil SLT tree could not be enumerated via HTML scraping. Counts come from the Git mirror, which may lag.

## 5. Other reimplementations and their compatibility testing

### Takeaway
Turso (formerly Limbo) is the only reimplementation found with serious SQLite-test reuse:
- it vendors 846 upstream Tcl files, runnable via a Tcl binding;
- it has about 9.3k converted/hand-written `.sqltest` cases with fresh-DB isolation;
- it runs deterministic simulation with a `--differential` mode against SQLite.

Its `.sqltest` corpus is the closest existing thing to "setup + query + expected result", but it is text-rendered and untyped.

### Cited Findings
- Turso claims SQLite compatibility validated "through differential testing against SQLite and ongoing work to pass the full SQLite TCL test suite". The simulator generates random interaction plans (statements + assertions) and has a `--differential` flag that runs the same plan on Limbo and SQLite and compares. Turso is also tested with Antithesis. — [Turso simulator README](https://github.com/tursodatabase/turso/blob/main/testing/simulator/README.md); [Introducing Limbo](https://turso.tech/blog/introducing-limbo-a-complete-rewrite-of-sqlite-in-rust)
- **[verified-local]** The `.sqltest` format uses these database types: `:memory:` (fresh per test), `:temp:`, `:default:` (pre-generated users/products DB), `:default-no-rowidalias:`, and a readonly path. Expected output is pipe-separated text rows. There is also `expect error {regex}`. — [turso dsl-spec.md](https://github.com/tursodatabase/turso/blob/main/testing/sqltest/docs/dsl-spec.md)
- Turso issue #1710 documents a case where `do_execsql_test_on_specific_db` in Turso's own tester.tcl behaved differently from SQLite on constraint errors. This is evidence that harness semantics (error propagation mid-script) matter. — [turso issue #1710](https://github.com/tursodatabase/turso/issues/1710)
- No evidence was found that sql.js, GlueSQL, CG/SQL or rqlite ported SQLite's Tcl tests into a neutral format. No sources were located in this session.

### Inferences
- Turso's `sqlite-sqltests/*.sqltest` could be imported cheaply (MIT license; verify). Treat them as inputs only and regenerate expectations with pinned native 3.51.0, since Turso may have fixed them to its own behavior or to a different SQLite version. They already come isolated per test, so no segmentation is needed. Notable file: `alter_table.sqltest` (223 tests), plus many `alter-*` regression files.
- Turso's `turso_tcl.c` is evidence that the "replace the `sqlite3` Tcl command" approach scales to the whole upstream suite. The same trick with a *logging* proxy over real SQLite is the recommended extraction route (section 2).

### Gaps
- Turso's license terms for the vendored upstream tests (SQLite's are public domain) and for its `.sqltest` corpus were not checked.
- sql.js, GlueSQL, CG/SQL and rqlite compatibility testing: not researched in depth. No findings.

## 6. TH3, dbsqlfuzz, fuzzdata*.db

### Takeaway
TH3 is proprietary and unavailable, yet it holds most requirement evidence (47.6%). The `fuzzdata*.db` files are about 46k fuzz scripts with no expected results, usable only as differential inputs, not as oracles.

### Cited Findings
- TH3 is about 76.9 MB / 1,055.4 KSLOC of C, with 50,362 distinct cases and about 2.4M instances for full coverage. dbsqlfuzz "mutates both the SQL and the database file at the same time", with 336 seed files and about 1 billion mutations per day. Historical AFL, OSS-Fuzz and dbsqlfuzz cases are rerun by `fuzzcheck` on every `make test`. — [How SQLite Is Tested](https://www.sqlite.org/testing.html); [TH3](https://sqlite.org/th3.html)
- fuzzcheck runs only "interesting" cases, i.e. those exhibiting previously unseen behavior. dbsqlfuzz inputs are text: a hex database description, a divider, then SQL. — [How SQLite Is Tested](https://www.sqlite.org/testing.html); [Chromium SQLite fuzz README](https://chromium.googlesource.com/chromium/src/+/lkgr/third_party/sqlite/fuzz/README.md)
- **[verified-local]** Each `test/fuzzdata{1..8}.db` has schema `db(dbid, dbcontent BLOB)`, `xsql(sqlid, sqltext)` and `readme(msg)`. `xsql` counts: 1:9,917; 2:9,959; 3:1 (+2,316 DB images); 4:2,575; 5:8,834; 6:3,896; 7:1 (+8,145 DB images); 8:749. The contents are heavily garbled (e.g. `PRAGMA synchrono�s=NO00;`), with no expected outputs. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)

### Inferences
- The fuzz corpora are useful later for differential robustness: model-vs-native on parse errors and error codes. They are useless as a positive semantic test source. Most scripts error early or depend on corrupt DB images.

### Gaps
- None critical.

## 7. Pitfalls when turning these into proof obligations

### Takeaway
The main hazards are:
- untyped, flattened Tcl results;
- shared per-file state;
- `ifcapable`/permutation dependence;
- unordered results;
- error text vs error code;
- nondeterministic functions;
- EXPLAIN/query-plan tests;
- schema-text (`sqlite_schema.sql`) exactness.

All can be neutralized by native re-execution plus filtering.

### Cited Findings
- **[verified-local]** Types and NULL are lost in `execsql` results. `catchsql` yields message text only. `do_test` expectations can be regex, glob, or numeric-tolerance (`/…/`, `~/…/`, `#/…/`). Such cases must be excluded or converted. — [tester.tcl](https://github.com/sqlite/sqlite/blob/master/test/tester.tcl)
- **[verified-local]** 774 of 1,195 files use `ifcapable`. 389 use `foreach`. 161 involve EXPLAIN or `do_eqp_test`. 56 mention `random()`, `datetime('now')`/`julianday('now')` or `sqlite_sequence`. alter3.test itself does `db close; forcedelete test.db; sqlite3 db test.db` mid-file, and uses `test2.db` with ATTACH. — [sqlite/sqlite test/](https://github.com/sqlite/sqlite/tree/master/test)
- `do_eqp_test`/`query_plan_graph` rewrite plan text and mask pointers. Plans are implementation detail, not semantics. — [tester.tcl](https://github.com/sqlite/sqlite/blob/master/test/tester.tcl)
- SLT `rowsort` sorts by strcmp on rendered text ("9" after "10"). Reals print as `%.3f`. — [SLT about.wiki](https://www.sqlite.org/sqllogictest/doc/trunk/about.wiki)
- The permutations mechanism (`::G(perm:presql)`, `permutation`) re-runs files under different PRAGMAs and configs. Extraction should run only the default permutation. — [tester.tcl](https://github.com/sqlite/sqlite/blob/master/test/tester.tcl)

### Inferences
- Row order: queries without ORDER BY usually return rowid/index order in SQLite, and tests often rely on it. Either:
  - (a) model the order the engine *actually* produces, which requires modeling scan order (hard); or
  - (b) mark such cases multiset-compare, unless the query has a total ORDER BY.

  Tag each case with `ordered: bool`, derived by checking for ORDER BY or by running under `PRAGMA reverse_unordered_selects=ON` natively: if the result changes, the order is unspecified.
- Floats: compare via `quote()` or hex (`printf('%!.17g')`), not Tcl rendering.
- Errors: record `sqlite3_extended_errcode`, primary code, and message. Decide whether the model must match message text. The user already models specific messages (duplicate column etc.), so keep text for DDL errors where it is stable.
- Schema text: ALTER/RENAME tests assert exact `sqlite_schema.sql` rewrites, including quoting and whitespace preservation. This is a large, precise sub-spec (e.g. altertab/altercol). Decide early whether the model tracks the SQL text.
- Pinning: generate the corpus from the `version-3.51.0` tag with a default-options testfixture. Record `sqlite_options`/`PRAGMA compile_options` in the corpus header. Drop anything guarded by non-default `ifcapable`.
- Nondeterminism filter: run each extracted case twice natively, plus once with `reverse_unordered_selects`. Drop or relax anything unstable.

### Gaps
- No quantitative measurement was made of how many relevant-file assertions depend on row order without ORDER BY.

## 8. Realistic scale estimates

### Takeaway
**[estimate]** Dynamic extraction from the 3.51.0 Tcl suite should yield roughly 15k–30k self-contained pure-SQL cases overall, and roughly 3k–6k for the DDL/DML/transaction/constraint/index/type/expression subset (before dedup). SLT adds millions of SELECT/expression cases, of which a few thousand deduplicated small-table cases are practical. Turso adds about 9.3k pre-isolated cases.

### Cited Findings
- Base numbers (all **[verified-local]** from sections 1, 4 and 5 unless noted):
  - 51,445 distinct Tcl cases, per sqlite.org — [testing.html](https://www.sqlite.org/testing.html)
  - about 47k static do_* call sites in total
  - 7,643 execsql/catchsql call sites in heuristic-clean files
  - about 4,260 call sites in 77 relevant files
  - 601 R-ids cited in e_*.test
  - 3,487 total requirements, of which 870 have Tcl evidence
  - SLT: 7.2M queries, 318 evidence queries
  - Turso: 9,302 sqltest cases

### Inferences
- **[estimate]** Of the about 47k Tcl call sites, perhaps 40–60% run only SQL on the main `db` connection with a default build, with no C-API commands, fault injection, second connection or file manipulation. Loop expansion roughly offsets the exclusions, giving about 15k–30k cases. This is consistent with the "clean" heuristic's 7.6k lower bound, which excludes whole files.
- **[estimate]** For the user's next scopes:
  - ALTER family: about 900 call sites, about 700 usable.
  - Constraints and indexes: about 1,000.
  - e_* files: about 1,000 incl. `do_createtable_tests` sub-cases.
  - Transactions/savepoints: about 300. Many use a second connection or file checks, so the yield is lower.
  - Types/affinity/cast/expr: about 600.
- **[estimate]** Suggested staged strategy:
  1. Build the logging proxy and run it on the 3.51.0 tag for the 77 relevant files. This yields JSONL traces.
  2. Build a native minimizer and re-oracle, producing typed expectations and error codes.
  3. Filter by the model's supported-statement grammar, so each case is labelled "in-scope now" or "future".
  4. Tag cases with R-ids from the nearest preceding `EVIDENCE-OF` comment, giving requirement coverage against the 3,487-row matrix.
  5. Import Turso `.sqltest` and SLT `evidence/` as secondary inputs, re-oracled natively.

### Gaps
- None of these yields were measured, because testfixture was not built in this session. A pilot run of the logging proxy on the ALTER files would calibrate the estimates.
