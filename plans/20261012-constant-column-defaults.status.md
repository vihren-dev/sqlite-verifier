# Constant-column-default status

Created 2026-10-12. Status: IN PROGRESS.
Task: [constant defaults](20261012-constant-column-defaults.task.md).
Source: [issue #14](https://github.com/vihren-dev/sqlite-verifier/issues/14).

## Progress

- 2026-10-12: Prepared the T14 outcome and acceptance record on accepted
  main `6441fc14`, in the reused completed `ci-split` workspace. Its previous
  checkout is retained by an archive bookmark. T18a is delivered; T07,
  T08 and T11 are preferred predecessors. Native investigation can proceed
  while T06 and PR #81 wait for owner input. No production representation
  is changed. The current and proposed resolution/default boundaries have
  been inspected before selecting native cases.

Decisions waiting for the owner:

- None for the native investigation. Final representation and codec
  changes retain the required owner review.

- 2026-10-12: Completed 260 bounded native observations across exact
  SQLite 3.51.0 and 3.46.0 pins, covering five affinities, six literal
  classes, optional NOT NULL, empty and populated tables, omitted INSERT
  values, and prohibited forms. Library hashes remain unchanged after the
  run. Raw typed cells, source identities, exact ADD commands, schema
  observations and extended error codes remain local in
  `build/20261012-column-defaults/native-defaults.json`. This is oracle
  investigation, not production-model acceptance.

  Both releases accept NOT NULL DEFAULT NULL on an empty table; a later
  omitted insert fails with the NOT NULL constraint code. They reject the
  same ADD on a populated table. CURRENT_TIMESTAMP and the probed
  expression defaults also succeed on empty tables and fail on populated
  tables. PRIMARY KEY and UNIQUE additions fail in both states. These
  findings require explicit model restrictions for unmodeled accepted
  forms, rather than invented engine errors. No production code changes.

Decisions waiting for the owner:

- None for this investigation. The existing final representation and codec
  review remains required after implementation.

- 2026-10-12: Extracted the unchanged Value declaration into a small
  core module so column metadata can use stored values without importing
  the table model. All qualified names, constructors and the declaration
  docstring retain their exact original bytes; codec source is unchanged.
  The package build list now includes the module, and its ownership test
  accounts for the additional core module. Final model-package, application
  runtime and public documentation builds pass. All 244 declarations are
  checked. Three actual isolated-package tests pass, including core/codec
  consumers and rejection of an application import. Initial missing-module
  build and wrong-runtime-root test attempts remain separate; corrected
  receipts are retained locally. No default admission or execution change
  is claimed by this foundation.

Decisions waiting for the owner:

- None for this representation-preserving extraction. T14 final default
  representation and codec changes retain their required owner review.

- 2026-10-12: Prepared constant-default metadata and codec round-trip
  cases in the model suite. The edits are uncommitted and unvalidated.
  The resource guard stops further validation at 9.95 GiB free, below the
  10 GiB requirement. A precise cleanup proposal selects only the completed
  T06 installed test's extracted Nix cache, 1,114,598,749 bytes. The
  original offline archive is retained and its checksum is verified; no
  source, installed runtime, GC root, test result or campaign record is
  selected. The enclosing directory has no open file handles. It is newer
  than the standing 24-hour allowance, so targeted approval is requested
  in `build/20261012-column-defaults/cleanup-proposal.json`. No deletion
  or validation occurs after the guard refusal.

Decisions waiting for the owner:

- Approval to delete that exact extracted cache, or hold T14 validation.

- 2026-10-12: The owner authorized the proposed cleanup. Deleted the
  completed T06 test's extracted cache after checking its identity, the
  retained archive checksum and open files. The deletion receipt records
  1,114,598,749 bytes removed. Nix garbage collection also removed 1,290
  unreachable paths and reported 851.65 MiB freed. The resource guard now
  passes with about 11.7 GiB free. Constant-default validation has resumed.
  Receipts and the garbage-collection log remain local under
  `build/20261012-column-defaults/`.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.
  The cleanup request above is resolved.

- 2026-10-12: The resumed runtime build failed before compilation because
  Nix could not connect to `/nix/var/nix/gc-socket/socket`. Its process
  exited with code 1. The initial failure is retained in
  `build/20261012-column-defaults/constant-runtime.log`. The constant-default
  edits remain unvalidated and uncommitted. Validation is held under the
  workspace rule for build-environment failures.

Decisions waiting for the owner:

- Retry the unchanged build once, or hold validation.
- Final review of the completed T14 representation and codec changes.

- 2026-10-12: The owner authorized one unchanged build retry. It passed
  and produced the complete runtime at
  `/nix/store/87dky0aaqs8xw5xw00nm5qgp27v1jzpb-sqlite-verifier-runtime-1`.
  ColumnDefault now retains a typed constant Value, and the codec derives
  scalar instances before the default instances that use them. Five scalar
  round trips and four corrupt-input refusals pass through compiled Lean
  checks. Together with the existing shared-shape checks, 15 tests pass.
  Another 15 suite-ownership and frontend-import checks pass. The checked
  public documentation covers all 245 declarations. Original and retry
  logs and test XML remain separate under the local build directory.
  This checkpoint adds representation and transport only; SQL admission,
  default execution and complete T14 acceptance remain unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.
  The build-retry request above is resolved.

- 2026-10-12: Independent review `20261012T094050Z-cc166681`
  reports the expected codec owner-review gate and one documentation
  omission. Updated the format guide with the constant payload, its
  affinity-applied meaning and an example. Final owner review is deferred
  until the complete T14 change is ready, as authorized in the task queue.
  This does not count as owner approval or completed T14 acceptance.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Review of the format correction found no must findings
  and one wording ambiguity. Clarified that each scalar default payload
  must be inside the constant wrapper; bare scalar values are not default
  encodings. Recorded the finding as fixed.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Corrected the format guide's positional reference to
  the value encodings below. The wrapper clarification review had no
  must findings and identified this reference as a should finding.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Final format-guide correction `1506856f` passes
  independent review `20261012T094328Z-1506856f` with no findings. The
  representation and transport checkpoint is committed and checked.
  Default execution, SQL admission, native conformance, preservation
  lemmas and end-to-end acceptance remain to be implemented.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Structural column extension now appends each stored
  constant default. Absent defaults still append NULL. Current-timestamp
  metadata is not evaluated; current SQL admission continues to exclude
  it and all new default syntax. Replaced the NULL-only row operation and
  projection helper with value-based operations, updating their callers
  and exact plain-words statements. Row identity, old-cell preservation,
  extension composition, table validity and old-field projection proofs
  compile. The new-column projection theorem applies to arbitrary stored
  constants and arbitrary old-field lists under width and freshness
  assumptions.

  Final runtime and documentation builds pass; all 246 declarations have
  checked documentation. Thirty-two existing codec, shape, ownership and
  frontend checks pass. The new compiled default-extension check passes
  after correcting fixture indentation, covering all five scalar storage
  classes, plain NULL extension, empty rows and both projection lemmas.
  Failed fixture attempts remain separate from corrected results. Logs and
  XML are local under `build/20261012-column-defaults/`. No native
  conformance, default SQL admission or complete T14 acceptance is claimed.

  The resource guard then failed at 9.52 GiB free. Used the owner's
  standing Nix garbage-collection authorization: removed 1,254 unreachable
  store paths and reported 1,342.64 MiB freed. The guard passes again.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Independent review `20261012T094947Z-d7006a12`
  has no must findings and requests a checked Column.extensionValue
  reference in the ADD-column theorem's plain-words statement. Prepared
  that correction. The resource guard refuses further builds at 9.74 GiB
  free. A documentation build was mistakenly launched after the refusal;
  it was stopped with SIGINT and exited with code 1. It is not acceptance.
  The correction remains unvalidated and uncommitted.

  A precise proposal selects eight superseded build symlinks, retaining
  the latest checked runtime and documentation links, all source commits,
  logs, XML and original archives. Unlinking them and then collecting
  unreachable Nix paths requires the requested targeted approval because
  T14 is still active. The proposal remains local at
  `build/20261012-column-defaults/superseded-links-cleanup-proposal.json`.

Decisions waiting for the owner:

- Approve the eight listed symlinks for cleanup, or hold validation.
- Final review of the completed T14 representation and codec changes.

- 2026-10-12: The owner approved the eight-link cleanup. Verified
  each symlink's inode and target before removing exactly the listed links.
  The current checked runtime and documentation remain retained. Nix
  garbage collection removed 50 unreachable store paths and reported
  1,446.01 MiB freed. The resource guard passes with about 11 GiB free.
  The approved cleanup receipt and garbage-collection log remain local.
  Resumed compilation of the pending checked docstring reference.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.
  The eight-link cleanup request is resolved.

- 2026-10-12: The resumed documentation build passes and checks
  all 246 public declarations. The ADD-column theorem now names
  Column.extensionValue through a checked Verso reference, resolving
  review finding `20261012T094947Z-d7006a12#1`. The interrupted pre-cleanup
  attempt remains separate from the successful approved retry log.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Docstring correction `52c3fc14` passes independent
  review `20261012T103240Z-52c3fc14` with no findings. The resource guard
  still passes. Default SQL admission and complete T14 acceptance remain
  unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Integrated main `5feb549e`, including delivered
  resolution core PR #81 and the accepted development-integrity policy.
  Retained the complete previous T14 checkout and pending review record
  under `archive/t14-before-resolution-integration-20261012`. Resolved
  the package list by retaining both resolution and the scalar Value
  module; the actual public import closure now contains 35 modules.

  Complete runtime and checked documentation builds pass. The inventory
  checks all 484 declarations. All 36 affected checks pass against the
  integrated runtime: exact constant extension, codec refusal and round
  trips, shared shape, neutral consumers, actual isolated package builds,
  forbidden application imports, suite ownership and frontend imports.
  Fresh logs and XML are in `build/20261012-t14-main-integration/`.

  The preceding untracked build directory was absent when integration
  validation began. Earlier raw T14 logs and native observations were not
  found in the workspace or local artifact directory. Source and status
  commits remain intact. Fresh checks above establish current integration
  acceptance only; the old raw native campaign must be regenerated before
  it can support final T14 acceptance. No cause for the disappearance is
  inferred. Free space is about 26 GiB and the resource guard passes.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Integration `c08ae90a` passes independent review
  `20261012T105613Z-c08ae90a` with no findings. Current main and the T14
  representation/projection changes now build together. Default SQL
  admission, the production resolution switch and full acceptance remain
  unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Added model-owned native oracle comparisons for six
  literal fixtures and five affinities on exact SQLite 3.51.0 and 3.46.0
  pins. Independently authored stored default metadata drives our Lean
  row-extension operation; native rowids and typed old/new cells supply
  the expected results. All 60 cases pass. Fifteen suite-ownership and
  frontend-import checks pass. The complete macOS model suite passes
  126 tests in its Nix sandbox, with fresh XML retained in its output and
  the local integration evidence directory. This validates structural
  extension given resolved metadata, not SQL admission or resolution.

  The owner starts ADR 0010 independently. Updated T14 acceptance to
  consume its case layout, proofs project, installed Lake packages and
  cache controls. This task does not duplicate that orchestration work.
  Model work continues; final command-line acceptance follows the relevant
  delivered interfaces. Existing source verify checks remain only while
  that deprecated command exists.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Native-comparison checkpoint `473b6d72` passes
  independent review `20261012T110554Z-473b6d72` with no findings. The
  complete 126-test macOS model suite and 60 direct native comparisons
  are acceptance for row extension given resolved defaults. SQL admission
  and the remaining end-to-end acceptance remain unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Regenerated native boundary evidence in
  `build/20261012-t14-default-phases/`. The bounded probe completes 280
  observations on pinned SQLite 3.51.0 and 3.46.0: fourteen ADD forms,
  five affinities, and empty or populated tables. The resource guard passes.
  Results retain each library path, binary hash, source identity, preparation
  code, step code, typed rows and omitted-insert result. The results file
  SHA-256 is `6b88bf5b7e1a8fbd811c59510ed6295a606d50bd4d978e83014a74f2a47dc139`.

  Both versions prepare NOT NULL DEFAULT NULL and the probed nonconstant
  defaults successfully. They accept the ADD on empty tables and fail at
  step on populated tables. PRIMARY KEY and UNIQUE additions fail during
  preparation for both table states. The ten subsequent omitted inserts
  into NOT NULL DEFAULT NULL columns fail with code 1299 as expected; these
  are recorded SQL refusals, not diagnostic failures. No diagnostic fails.

  The comparison expression DEFAULT (1=1) exposes a current resolution
  defect: constantDefault classifies it as nonconstant, and resolveAddColumn
  predicts a preparation error. Both engines prepare it successfully and
  accept it on an empty table. Admission work must correct this distinction
  while retaining supported-domain refusal for expressions the model does
  not evaluate. This evidence determines the next change; it is not an
  additional passing model test or completed T14 acceptance.

  Corrected the current task's stale statement that PR #81 awaits review.
  It is merged; the production resolution switch remains unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Corrected default preparation classification in the shared
  resolution context. Constant comparisons now pass preparation eligibility;
  identifiers nested inside signs or comparisons fail it. A bare identifier
  keeps SQLite's default-text behavior. ADD resolution still refuses these
  unmodeled defaults through its supported-domain check instead of inventing
  a preparation failure. CREATE resolution uses the same corrected predicate.

  Sixteen new model-owned regressions compare the predicate and actual ADD
  resolution with preparation on both pinned native engines. The comparison
  case fails against the retained pre-fix runtime for the intended predicate
  mismatch. All sixteen pass with the correction. The final runtime builds,
  all 485 public declarations pass checked documentation, and the complete
  macOS model suite passes 142 tests in the Nix sandbox. Eleven test-ownership
  and frontend checks also pass. Evidence is retained under
  `build/20261012-t14-default-phases/`; final runtime, documentation and model
  outputs are linked as `build/t14-resolution-final` and its numbered outputs.
  No Linux acceptance or completed default execution is claimed.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Independent review of `833da85c` found that SQLite treats
  unquoted TRUE and FALSE as constants inside default expressions. Added
  that exception with case normalization and five more syntax fixtures,
  including quoted names. Both review findings are recorded as fixed.
  The predicate and ADD resolver now pass all 26 native comparisons.

  The first expanded suite exposed a test proof that ordinary decide could
  not reduce through identifier normalization. Evaluated results matched
  SQLite. Changed the assertion to kernel reduction and reran acceptance.
  The final sandboxed macOS model suite passes all 152 tests. The runtime
  builds and checked documentation covers all 485 public declarations.
  Final outputs use `build/t14-resolution-reviewed`; logs are in
  `build/20261012-t14-default-phases/reviewed-build.log`. Earlier failed
  attempts remain in the evidence directory and are not counted as passes.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Review of `6256d886` confirms both earlier findings are
  fixed. It requests a named predicate for SQLite's boolean keyword names.
  Extracted booleanKeywordName, which normalizes the name once, and recorded
  that finding as fixed. The final runtime and documentation build; all
  486 public declarations have checked documentation. All 26 default
  resolution comparisons pass against this runtime. The preceding full
  152-test model result remains evidence for the semantic correction;
  the predicate extraction has a fresh build and focused regression run.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.

- 2026-10-12: Predicate cleanup `041748db` passes independent review
  `20261012T113727Z-041748db` with no findings. All findings from this
  default-classification correction are resolved. Constant-default SQL
  execution, the production resolution switch, and complete T14 acceptance
  remain unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: PR 115 is merged as 780fb214. The storeValue dependency is
  delivered. The task file now names the delivered Syntax.Expr default
  representation and Row.Stored requirement. The next production change
  must preserve stored form for old rows extended with a constant default.
  This workspace still contains the reviewed classification work at 4a4f3f56;
  it has not been integrated with 780fb214. The older validation records do
  not establish acceptance on current main.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Preserved the earlier T14 line at bookmark
  archive/t14-before-store-value-integration-20261014 (bad64185), then started
  the current change from merged main 780fb214. The old resolved-default
  field and conversion implementation remain historical work on that line.
  The active task uses Syntax.Expr and the delivered storeValue instead.

  Ported the reviewed preparation correction and its 26 native comparisons.
  Constant equality defaults are eligible; unknown names nested in signs or
  equality are not. Unquoted TRUE and FALSE remain constant keywords. Other
  expression forms keep main's existing permissive classification followed
  by model restriction. This change does not add default execution.

  The retained test first fails against the unchanged default classifier in
  the T08 integration runtime: SQLite prepares DEFAULT (1=1), but the model
  reports defaultNotConstant. The corrected implementation passes the full
  sandboxed macOS model suite: 133 tests in 156.54 seconds, including all 26
  comparisons. Runtime libraries and all 790 checked public declarations
  compile. Twelve suite-ownership and frontend checks pass. The protected
  verdict has unchanged agreement counts and lock, with no disagreements.

  Logs: build/t14-default-main-regression-checked-20261014.log,
  build/t14-main-classification-20261014.log,
  build/t14-main-source-20261014.log and build/t14-main-verdict-20261014.log.
  The first regression command used another workspace's runtime symlink,
  which made pytest load both conftest files. Using the immutable store path
  fixed that invocation; it is not counted as a product failure. Independent
  review of this port follows its commit. Full default execution and final
  cross-platform acceptance remain unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Commit d4aee20e passes independent review
  20261014T155709Z-d4aee20e with no required findings and two documentation
  recommendations. Fixed both: callers check quoting, and the predicates
  describe SQLite's constant-default preparation rule within their stated
  classification scope. Both findings have resolution records. Public
  documentation compiles in build/t14-main-review-docs-20261014.log.
  Implementation and test behavior are unchanged from the passing 133-test
  run. The documentation correction requires its own independent review.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Documentation correction 7044c7d6 passes review
  20261014T155857Z-7044c7d6 with no findings. The preparation correction on
  current main is tested and reviewed. The task bookmark records this
  checkpoint. Constant-default admission, execution, preservation and
  installed acceptance remain unfinished. The older implementation and
  evidence remain on the archive bookmark named above.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Added a shared literal-default evaluator in Resolution/Defaults.lean
  and moved defaultValue out of Writes.lean. It evaluates NULL, numeric, text
  and blob literals, signed numeric literals and bare identifiers, including
  the TRUE/FALSE exception. Time values and compound expressions retain model
  restrictions. No resolved-default metadata or second affinity implementation
  was added. INSERT's existing fullRow applies storeValue after this evaluator.

  Ten native-comparison tests cover 12 defaults across five affinities and
  both pinned engines: 120 comparisons of omitted INSERT values and storage
  classes. They fail against the prior runtime's unmodeledDefault refusal and
  pass against the new evaluator. All 25 focused comparisons and package,
  ownership and frontend checks pass. All 143 sandboxed macOS model tests pass.
  Runtime libraries and all 791 public declarations compile. The protected
  verdict retains its agreement counts and lock, with no disagreements.

  The first build exposed the old proof assumption that defaultValue fails
  only with model restrictions. The corrected proof also covers the numeric
  literal preparation error for an oversized hexadecimal literal. Its initial
  tactic attempt failed; the checked correction reduces the numeric conversion
  before splitting its result. A test import from the old column codec was
  corrected to conformance.case_format. These failures are not passing checks.

  Evidence: build/t14-literal-defaults-before-checked-20261014.log,
  build/t14-literal-defaults-final-20261014.log,
  build/t14-literal-defaults-focused-20261014.log,
  build/t14-literal-default-model-20261014.log and
  build/t14-literal-default-verdict-20261014.log. Independent review follows
  the commit. SQL catalog admission still refuses these literal defaults;
  ADD COLUMN execution and preservation are not changed by this unit.
  Those integrations and final cross-platform acceptance remain unfinished.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Review 20261014T161238Z-4c9108df found no required changes
  and two recommendations for the hexadecimal error path. The documentation
  now identifies this as SQLite's preparation error. Four new comparisons
  cover positive and negative oversized hexadecimal defaults on both engines.
  SQLite accepts each table definition and rejects the omitted-value INSERT
  during preparation; fullRow produces the matching preparation error and
  message. All four pass in build/t14-literal-hex-review-checked-20261014.log.
  The first test attempt imported a conformance module outside the fixture's
  library path; the corrected test imports the model's error messages directly.

  All 791 public declarations compile in
  build/t14-literal-review-docs-20261014.log. Both findings are recorded as
  fixed. Production behavior is unchanged from the passing 143-test run;
  the four added cases have fresh focused results. Independent review of
  this correction follows its commit.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Correction 80873314 passes review
  20261014T161540Z-80873314 with no findings. The shared literal-default
  evaluator, its error proof and native comparisons are tested and reviewed.
  Next acceptance remains SQL catalog admission, ADD COLUMN row extension
  with stored-form preservation, and the installed example on both platforms.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: GitHub main advanced to c10fe001, the merge of PR 116.
  Integrated it before extending catalog admission. It supplies the approved
  obligation and row-write corpora, their claims and lock, and includes both
  corpora in the frozen test inputs. These files exactly match merged main;
  this task adds no judge or claim change. The merge has no conflicts.

  The protected verdict passes, including all 24 row-write cases in corpus 11
  and the two correctly unsupported obligation cases in corpus 10. Existing
  corpus counts are unchanged. The sandboxed macOS frozen suite passes.
  Evidence is in build/t14-pr116-verdict-20261014.log and
  build/t14-pr116-frozen-20261014.log. Catalog-admission code is unchanged
  at this checkpoint; integration review follows the commit.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: Integration e30196a9 passes independent review
  20261014T162046Z-e30196a9 with no findings. The frozen suite passed all
  146 tests in 68.46 seconds. The active bookmark includes the approved
  corpus update. Catalog admission and ADD COLUMN execution remain next.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-14: The resource guard stopped new build work at 9.62 GiB free.
  Under the owner's standing cleanup approval, Nix garbage collection
  deleted 118 unreachable store paths and freed 5,386.12 MiB. Every deletion
  is recorded in build/t14-space-cleanup-20261014.log. No workspace test
  directory or retained build link was deleted. The resource guard passes
  after cleanup. Catalog-admission implementation has not started yet.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Catalog admission builds, including the 791 checked public
  declarations. Its focused run fails all five affinity parameters; 15 other
  checks pass. The first NULL-default case disagrees because Native.columnMatches
  and Predict.nativeColumn still handle only CURRENT_TIMESTAMP. This is not a
  passing feature checkpoint. The admission edits remain in the working copy.

  A bounded probe with the pinned runtime confirms that X'00ff' and x'00FF'
  produce the same expression tree but different native default metadata.
  The same loss occurs for - 7 and -7. Bracketed and backtick-quoted true
  also lose their quote kind. Evidence is in
  build/t14-default-spelling-20261015.json. The next change must preserve
  source spelling through syntax, codecs and catalog before extending the
  two conformance adapters. The judge and its lock remain unchanged.
  The pending admission test now includes these spelling cases.

  Build and failure logs are build/t14-default-admission-build-20261014.log
  and build/t14-default-admission-focused-20261014.log. The initial spelling
  probe used unsupported INSERT DEFAULT VALUES; its corrected run uses
  SELECT and all ten cases reach the frontend successfully.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: The working copy now carries each default's source text from
  frontend syntax through the catalog to Native.columnMatches and
  Predict.nativeColumn. The judge and native recorder are unchanged.
  The runtime builds, the generated-source round trip passes, and all 795
  public declarations have checked documentation. A constructor-based Repr
  fixes invalid indentation from printing the new nested default record.

  The focused run passes 48 frontend checks. For each of five affinities,
  the first 11 admission cases agree and their generated terms pass the
  kernel. This includes the previously lost blob casing and sign spacing.
  All five parameters then fail at the bracket-quoted [true] default.
  The expression tree marks it as not double-quoted, so the literal evaluator
  still treats it as the boolean keyword. Preserve this quote distinction
  in default evaluation next. The changed transport also needs its version
  updated before acceptance. Production and test edits remain uncommitted
  because the admission suite is not yet passing.

  Evidence: build/t14-default-spelling-build-20261015.log and
  build/t14-default-spelling-focused-20261015.log (five failed, 48 passed
  in 89.03 seconds). The temporary generated-source diagnostic was removed.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Written default evaluation now treats bracketed and backtick
  identifiers as text. The error-preservation proof compiles. Script records
  use version 3, and conformance cases use version 5 to identify the changed
  default syntax. Retained native records are unchanged. Their replay tests
  permit only the transport version difference; all other fields must match.

  The focused run passed all 54 tests in 137.97 seconds, including 85
  admission cases with kernel checks and a mutation that changes default
  spelling without changing blob bytes. The broader harness passed all 179
  tests in 6.21 seconds after its version assertion and restriction example
  were corrected. CURRENT_DATE now exercises the unmodeled-default restriction.

  The full model run is still active. Its retained-fixture assertions used
  the old version and failed; the assertion correction is in the working
  copy for the next run. Remaining model checks have reached the new admission
  tests. Do not treat this run as passing. Build and test evidence is in
  build/t14-quoted-defaults-build-20261015.log,
  build/t14-quoted-defaults-focused-20261015.log and
  build/t14-default-admission-acceptance-20261015.log.
  Full model revalidation, generated-input checks, protected verdict and
  independent review remain before the feature commit is accepted.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Literal catalog admission is ready for independent review.
  The sandboxed macOS model suite passes all 153 tests in 343.59 seconds.
  The harness passes all 179 tests, and the 16 generated-input parity checks
  pass in 19.30 seconds. All 796 public declarations have checked documentation.
  The protected verdict passes with unchanged corpus counts. The judge, claims,
  lock and retained native records are unchanged.

  Evidence: build/t14-default-admission-final-20261015.log,
  build/t14-default-generated-inputs-final-20261015.log and
  build/t14-default-verdict-20261015.log. The first generated-input invocation
  selected the conformance runtime, which excludes examples. The passing run
  uses the complete runtime. This was a test invocation correction.

  This checkpoint admits literal defaults in catalog schemas and supplies
  omitted INSERT values. Source spelling survives syntax, codecs, catalog
  comparison and prediction. Quote delimiters distinguish literal text from
  boolean keywords. A source-spelling mutation with equal blob bytes is rejected
  by the catalog comparison and has a kernel-checked disagreement.
  ADD COLUMN row extension, preservation proofs, installed examples and final
  two-platform acceptance remain. Independent review follows this commit.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Independent review 20261015T080621Z-cb3c4d6e reports no
  required fixes and two recommended changes. Both are fixed: Native names
  and documents the keyword-default list, and writtenDefault lists every
  expression constructor explicitly. The review records mark both findings
  fixed. This changes structure and documentation, not evaluation rules.

  The rebuilt runtime and all 796 public documentation checks pass. The
  focused INTEGER admission and source-spelling mutation tests pass in
  29.22 seconds. Evidence is in build/t14-default-review-fix-build-20261015.log
  and build/t14-default-review-fix-tests-20261015.log. The correction receives
  its own independent review next.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Correction 503960a1 passes independent review
  20261015T081030Z-503960a1 with no findings. The literal catalog and omitted
  INSERT checkpoint is reviewed. ADD COLUMN execution, preservation and
  installed acceptance remain; T14 is still in progress.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Both pinned engines confirm that ADD COLUMN readback differs
  from omitted INSERT evaluation. TEXT DEFAULT 1.50 retains the spelling
  1.50, and an oversized hexadecimal default remains readable. Negating
  that hexadecimal text gives zero. The pinned sqlite3ValueFromExpr source
  explains these paths. NOT NULL with a NULL default succeeds on an empty
  table and fails during stepping on a populated table. Evidence is in
  build/t14-add-default-boundaries-20261015.json and
  build/t14-add-numeric-defaults-20261015.json.

  ReadDefaults.lean implements readback using the existing numeric parser
  and storeValue. INSERT evaluation is unchanged. The new regression first
  failed when it used INSERT evaluation: 1.50 became 1.5 in a TEXT column.
  With the reader, all 290 comparisons pass across both engines and five
  affinities. They cover numeric spelling, separators, signed boundaries,
  hexadecimal overflow, quoted booleans and ordinary literal classes.

  The reader's two stored-form lemmas compile. The runtime and all 800 public
  documentation checks pass. The 11 focused reader and closure checks pass
  in 14.73 seconds, and all three standalone package checks pass in 9.08
  seconds. Evidence is in build/t14-default-reader-build-20261015.log,
  build/t14-default-reader-tests-20261015.log and
  build/t14-default-reader-package-20261015.log. Package consumer tests also
  exposed two old script-version assertions; both now use version 3. Actual
  installed-runtime acceptance remains a later T14 gate.

  This is the readback primitive, not ADD COLUMN execution. The next change
  must replace NULL-only row extension, preserve old cells and rowids, and
  retain the old catalog when ADD fails during execution. Independent review
  follows this commit.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Reader commit 2068d0e0 passes independent review
  20261015T102813Z-2068d0e0 with no findings. The reviewed helper and its
  stored-form lemmas are ready for ADD COLUMN integration. Execution and
  catalog handling on a failed ADD remain unchanged at this checkpoint.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Fetched main 32da9f9a and synchronized the shared main
  checkout. DELETE, INNER and LEFT joins, and USING and NATURAL joins are
  delivered. RIGHT and FULL joins remain in open PR 125. These changes do not
  deliver ADD COLUMN defaults: main still extends rows with NULL.

  This task retains reviewed checkpoint 48d71277 and its pending review record.
  It has not integrated the changes after c10fe001. The next integration must
  preserve the new write syntax, query scope, codecs and approved corpora.
  Existing test results remain evidence for their recorded revisions only.
  No feature code, judge lock or frozen evidence changed during this sync.

Decisions waiting for the owner:

- Final review after ADD COLUMN execution, preservation and installed
  acceptance are complete. No new design decision is required now.


- 2026-10-15: Integrated main 32da9f9a into the working change. Resolved
  conflicts in default classification, INSERT defaults, prediction and package
  ownership. The new qualified-name expression is explicitly rejected as a
  default; literal and source-spelling behavior is retained. The core import
  count now includes both the merged query modules and the default helpers.

  The conformance runtime and checked public documentation build successfully.
  The judge, claims and corpora 12 through 14 exactly match main. Model,
  harness, frozen and protected-verdict checks are running; this is not yet
  an accepted or independently reviewed integration. Logs are
  build/t14-main-integration-20261015.log, build/t14-main-tests-20261015.log
  and build/t14-main-verdict-20261015.log. The first build attempt lacked
  sandbox access to the Nix daemon; the authorized daemon-access run passed.

Decisions waiting for the owner:

- Final review after complete ADD COLUMN and installed acceptance.


- 2026-10-15: Integration validation now passes all 884 public documentation
  checks, 146 frozen tests in 54.83 seconds and 182 harness tests in 5.77
  seconds. The protected verdict passes, including all 15 DELETE cases,
  21 join cases and 22 USING/NATURAL cases. The 169-test model suite remains
  active. Integration is uncommitted pending that result and independent review.

Decisions waiting for the owner:

- Final review of the completed T14 change, after the remaining acceptance.


- 2026-10-15: The integrated model suite passes all 169 tests in 302.60
  seconds. All three standalone package tests pass in 6.43 seconds, including
  the 69-module import closure and the isolated consumer. Together with the
  passing harness, frozen suite, documentation and protected verdict above,
  this completes local macOS integration checks. Independent review follows
  the integration commit. Evidence is in build/t14-main-tests-20261015.log
  and build/t14-main-package-20261015.log. This is not Linux or installed
  ADD COLUMN acceptance; those task gates remain open.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Independent review 20261015T104503Z-50999f9f reports no
  required fixes and one documentation recommendation. Updated the default
  classifier's docstring to state that qualified column references are
  nonconstant defaults under SQLite's rule. The implementation is unchanged.
  Checked documentation is rebuilt before committing this correction.

Decisions waiting for the owner:

- Final review of the completed T14 change.


- 2026-10-15: All 884 checked public declarations compile after the
  classifier documentation correction. The recommendation is recorded as
  fixed. Evidence: build/t14-main-review-docs-20261015.log. Independent review
  of the correction follows its commit; no behavior changed.

Decisions waiting for the owner:

- Final review of the completed T14 change.


- 2026-10-15: Correction fbc79054 passes independent review
  20261015T104646Z-fbc79054 with no findings. Integration 50999f9f and its
  documentation correction are accepted local checkpoints. The next work is
  value-based row extension, ADD COLUMN execution and failure catalog handling,
  with preservation proofs and installed acceptance. No task completion or
  final owner approval is claimed.

Decisions waiting for the owner:

- Final review of the completed T14 representation and codec changes.


- 2026-10-15: Replaced NULL-only row extension with Row.appendValues and
  column/value pairs in Table.appendColumns. The table operation applies each
  new column's affinity. Generalized extension composition, old-cell and rowid
  preservation, stored-form validity and the new-column projection. Existing
  execution supplies NULL explicitly, so SQL behavior is unchanged in this unit.
  Updated application and candidate proof consumers; no approved source changed.

  The runtime and checked documentation compile. The new compiled regression
  checks affinity conversion, row order, rowids, old and new projections, keys,
  empty inputs and changed values. Its first attempt had a record-indentation
  error; the corrected fixture and all 16 generated-input checks pass. Another
  25 shape, ownership and frontend checks pass. The protected verdict passes
  with unchanged counts and lock. The full model suite is still running.

  The allowed-failure bundle check passes. Atuin's CLI check exposed inference
  of the old column-list argument; the candidate now supplies its column/value
  list explicitly. Its rebuilt consumer remains to be rechecked. Logs are
  build/t14-value-extension-20261015.log,
  build/t14-value-extension-tests-20261015.log,
  build/t14-value-extension-consumers-20261015.log,
  build/t14-value-extension-cli-20261015.log and
  build/t14-value-extension-verdict-20261015.log. This unit remains uncommitted
  until the remaining tests and subsequent independent review are complete.

Decisions waiting for the owner:

- Final review of completed T14. No new design decision is needed for this unit.


- 2026-10-15: Atuin needed both a column/value extension witness and an
  explicit column/value argument for Conforms.appendAt. Without the latter,
  Lean exhausted its heartbeat limit during inference. Both are corrected;
  no timeout was raised. The public Atuin verification test passes in 12.58
  seconds (build/t14-value-extension-atuin-explicit-20261015.log).

  The sandboxed model run completed with 169 passes and one failure in
  test_stateful_modes[True]. Its add_unpadded mutation still searched for the
  old appendColumns call. Updated that source anchor to the pair syntax;
  the injected mutant still adds metadata without extending rows. Both
  stateful modes are being rerun. The first focused invocation selected the
  CLI runtime, which has no conformance runner. Its corrected invocation
  uses the conformance runtime; no environment component is missing.
  Evidence: build/t14-value-extension-model-20261015.log and
  build/t14-value-extension-mutation-checked-20261015.log.

Decisions waiting for the owner:

- Final review of completed T14. The current unit still awaits its checks
  and independent review.


- 2026-10-15: Both stateful modes pass in 14.31 seconds after the mutation
  anchor correction, including detection of missing appended cells. The other
  169 tests passed in the earlier full model run. This is a focused correction
  result, not a second complete suite run. All 884 public documentation checks,
  the runtime, generated-input checks, Atuin verification, allowed-failure
  bundle and protected verdict pass. Approved source files, baselines, judge
  and frozen evidence are unchanged. The structural unit is ready for its
  commit and independent review. ADD COLUMN default execution remains next.

Decisions waiting for the owner:

- Final review of completed T14.


- 2026-10-15: Structural commit 5ec2c001 passes independent review
  20261015T110054Z-5ec2c001 with no findings. The row/value extension,
  stored-form validity and projection proofs are ready for ADD COLUMN
  execution. The next unit must call readDefaultValue, distinguish empty
  from populated tables for NOT NULL with NULL, and preserve the original
  catalog when execution fails. No installed default-example acceptance or
  final owner approval is claimed.

Decisions waiting for the owner:

- Final review of completed T14.


- 2026-10-15: Conformance comparison and prediction now select the preceding
  resolution state for a failed statement. Successful observations use the
  resulting state. The shared helper retains both the visible catalog and
  the saved transaction catalog. Resolution-state documentation now explains
  that resolution alone assumes successful execution.

  A compiled regression uses distinct catalogs to detect the wrong selection
  in compareSteps and predictedSteps, checks a successful prefix, and rejects
  changed native tables. These are synthetic consumer checks, not native ADD
  acceptance. The regression and all 11 existing pipeline tests pass in 11.88
  seconds. The runtime builds and the protected verdict passes with unchanged
  counts. Public documentation remains checked. Evidence is in
  build/t14-failed-catalog-build-20261015.log,
  build/t14-failed-catalog-tests-20261015.log and
  build/t14-failed-catalog-verdict-20261015.log. The judge and frozen evidence
  are unchanged. Independent review follows this prerequisite commit.
  ADD COLUMN default execution and its native tests remain next.

Decisions waiting for the owner:

- Final review of completed T14.


- 2026-10-15: Failure-catalog commit d26739b3 passes independent review
  20261015T110601Z-d26739b3 with no findings. Both conformance consumers now
  retain the pre-statement catalogs on failure. The next unit can connect
  default readback and value-based extension to ADD COLUMN execution, with
  native cases for successful and failed additions inside and outside transactions.

Decisions waiting for the owner:

- Final review of completed T14.


- 2026-10-15: ADD COLUMN now constructs literal default metadata, uses
  readDefaultValue during execution and appends its value through the reviewed
  extension primitive. NOT NULL with a NULL readback fails on populated tables
  with a distinct execution error and succeeds on empty tables. Unsupported
  default evaluation remains a model restriction. Updated support predicates,
  atomicity and preservation proofs, application examples and the mutation
  anchor. Approved sources, baselines and judge files are unchanged.

  Initial builds exposed missing proof case splits and application simplifications;
  these are fixed. The runtime, conformance runtime and checked documentation
  build successfully in build/t14-add-defaults-build4-20261015.log. Earlier
  failed logs are retained separately. An initial combined command did not start
  because automatic permission review timed out; separate edits and the permitted
  build retry succeeded.

  The new native suite has 170 comparisons across both pinned engines and all
  five affinities. It covers literal values, NOT NULL/NULL on empty and populated
  tables, a failed ADD after a successful prefix inside a transaction, and
  rollback. The suite is running with kernel checks of each comparison in
  build/t14-add-defaults-native-20261015.log. This feature is uncommitted and
  has not passed native acceptance or independent review. Broader regressions,
  an installed example and both-platform acceptance remain.

Decisions waiting for the owner:

- Final review of completed T14.


- 2026-10-15: The native suite stopped at the first affinity/version pair.
  Its first 11 cases passed with kernel proofs, including NOT NULL DEFAULT 7.
  NOT NULL DEFAULT NULL on a populated table disagreed. The resource guard
  then stopped builds at 8.20 GiB free. Under the standing cleanup approval,
  Nix garbage collection removed 10,698 unreachable paths and freed 12,641.55
  MiB. The complete deletion log is build/t14-add-defaults-cleanup-20261015.log;
  the resource guard passes again. No retained build link or evidence was removed.

  The detailed failure shows matching rows, catalog, primary code 1 and step
  phase. SQLite exposes an output column named by its internal RAISE expression.
  The pinned sqlite3AlterFinishAddColumn calls sqlite3ErrorIfNotEmpty, which
  compiles SELECT raise(ABORT, message) for NOT NULL with a NULL default. Added
  that output-name rule to statementOutput for both empty and populated tables.
  The native observation remains unchanged. The corrected runtime is building.
  Evidence: build/t14-add-defaults-disagreement-20261015.json and
  build/t14-add-defaults-output-build-20261015.log. The test now retains a JSON
  failure record instead of relying on truncated assertion output.

Decisions waiting for the owner:

- Final review of completed T14. Native acceptance remains incomplete.


- 2026-10-15: The conformance runtime with the ADD empty-table-check output
  rule builds successfully. Garbage collection required rebuilding several
  application dependencies; no compilation failure occurred. The complete
  native default suite is running again in
  build/t14-add-defaults-native-output-20261015.log. Native acceptance is not
  yet established, and the feature remains uncommitted.

Decisions waiting for the owner:

- Final review of completed T14.


- 2026-10-15: The corrected native ADD COLUMN suite passed all ten
  parameter groups in 239.54 seconds on macOS. These groups cover 170 cases
  across both pinned SQLite versions and five affinities, with kernel checks.
  Evidence: build/t14-add-defaults-native-output-20261015.log.

  Revalidated and removed 301 temporary pytest directories whose complete
  contents were older than 24 hours, under the existing cleanup approval.
  The inventory and per-directory deletion log are
  build/t14-old-test-cleanup-20261015.json and
  build/t14-old-test-cleanup-deleted-20261015.jsonl. Nix garbage collection
  then removed 1,751 unreachable paths and freed 10,731.79 MiB; its full log
  is build/t14-followup-gc-20261015.log. No retained build link was removed.
  Free space rose to about 16 GiB and tools/check_resources.py passed.

  The full model suite is running against build/t14-add-defaults-output,
  with a 600-second limit. Its log is
  build/t14-add-defaults-full-model-20261015.log. No full-suite result is
  claimed yet. Feature changes remain uncommitted pending these checks.
  Main has advanced to a2f480bd through PR 127; this task still needs
  integration with those RIGHT/FULL join changes after its current checks.

Decisions waiting for the owner:

- Final review of completed T14; implementation and acceptance are unfinished.


- 2026-10-15: The harness run passed 181 tests and failed its old count
  of unsupported cases. Fresh per-case replay confirms that the four NOT NULL
  ADD cases now agree: empty and populated tables, with and without explicit
  DEFAULT NULL. Updated the expected counts and added checks for these names.
  The resolution coverage test also expected the populated-table failure to
  remain unsupported. Both coverage files now pass all four tests. Evidence:
  build/t14-add-defaults-boundaries-20261015.json and
  build/t14-add-defaults-boundary-check-20261015.log.

  The preparation boundary test expected every accepted default to remain
  unsupported. It now checks whether resolution invents a preparation error,
  allowing both modeled literals and supported-domain refusals for other
  accepted expressions. All 26 pinned-engine preparation cases pass in
  build/t14-add-defaults-resolution-check-20261015.log. Native observations,
  frozen corpora, judge claims and the judge lock are unchanged.

  The original full model process remains active and retains the obsolete
  assertions it collected at startup. Its result is pending. Atuin, generated
  inputs, test ownership and frontend checks are also running in
  build/t14-add-defaults-consumers-20261015.log. These test corrections and
  the ADD implementation remain uncommitted pending regression acceptance.

Decisions waiting for the owner:

- Final review of completed T14; acceptance remains unfinished.


- 2026-10-15: Consumer checks passed 39 tests and failed one stale Atuin
  expectation that a literal default is unsupported. Retained the unsupported
  check with CURRENT_TIMESTAMP and added a separate kernel test that a changed
  literal default rejects the unchanged proof. Both default tests pass in
  8.62 seconds. Evidence: build/t14-add-defaults-consumers-20261015.log and
  build/t14-add-defaults-atuin-default-check-20261015.log.

  The protected Nix verdict passes with unchanged claims, corpora and lock.
  Corpora v3, v4, v5 and v6 now have 60, 30, 327 and 38 agreeing cases,
  respectively; no corpus has a disagreement or harness error. Other counts
  remain unchanged. Evidence: build/t14-add-defaults-verdict-20261015.log.
  The full model run remains active in its final native-default groups.

Decisions waiting for the owner:

- Final review of completed T14; full regression acceptance remains pending.


- 2026-10-15: The original full model run finished with 177 passes and
  four failures in 540.53 seconds. All 170 new native-default cases passed.
  Three failures were the coverage and preparation expectations corrected
  above. The fourth was a trace-mutation test: adding NOT NULL now disagrees
  with the unchanged trace instead of being unsupported. Updated that verdict
  and retained its negative kernel check. A fresh full run is active in
  build/t14-add-defaults-full-model-corrected-20261015.log, with the same
  600-second limit. The combined frozen and harness suites are running in
  build/t14-add-defaults-frozen-harness-20261015.log. No full passing result
  is claimed before these processes finish.

Decisions waiting for the owner:

- Final review of completed T14; acceptance and independent review remain.


- 2026-10-15: All 328 frozen and harness tests pass in 71.79 seconds,
  including the corrected authored boundary checks. Evidence:
  build/t14-add-defaults-frozen-harness-20261015.log. The corrected full
  model run remains active, with its earlier failed assertions now passing.

  Self-review found that primaryCode still used a catch-all for execution
  errors. Listed all constructors explicitly, including nullColumnDefault,
  as required by review condition R5. The error codes are unchanged. The
  conformance rebuild is running in
  build/t14-add-defaults-exhaustive-build-20261015.log. It needs focused
  error/trace checks before the implementation commit.

Decisions waiting for the owner:

- Final review of completed T14; implementation review and acceptance remain.


- 2026-10-15: The exhaustive error-code mapping builds successfully. All
  21 focused pipeline, phase, trace, failed-catalog and authored-boundary
  tests pass in 14.11 seconds against that runtime. The protected Nix verdict
  also passes for this final mapping, with the same counts as the previous
  run and unchanged judge inputs. Evidence:
  build/t14-add-defaults-exhaustive-check-20261015.log and
  build/t14-add-defaults-exhaustive-verdict-20261015.log. The corrected full
  model run is still active without failures; no final pass is claimed yet.

Decisions waiting for the owner:

- Final review of completed T14; final regression and independent review remain.


- 2026-10-15: The corrected full model suite passed all 181 tests in
  523.24 seconds, within the unchanged 600-second limit. It includes all
  170 native ADD COLUMN cases and their kernel checks. Evidence:
  build/t14-add-defaults-full-model-corrected-20261015.log. This full run
  used the output-corrected runtime. The final, behavior-preserving exhaustive
  error mapping separately passed its rebuild, 21 focused checks and the
  protected verdict, as recorded above.

  This implementation checkpoint adds literal ADD COLUMN execution, populated
  NOT NULL failure, unchanged catalogs after failure, row and projection
  preservation, and the native output-name rule. All 328 frozen/harness tests
  pass. Consumer checks passed 39 tests; their one obsolete default expectation
  was corrected and both replacement default scenarios pass. Public runtime
  and checked documentation builds passed before the mapping-only change.
  No approved source, baseline, corpus, claim or judge-lock file changed.

  The implementation is ready for independent review. T14 remains incomplete:
  integrate main through the new joins, add the public NOT NULL DEFAULT case,
  verify the offline installed example on both platforms, and obtain final
  owner review. Existing evidence does not claim those results.

Decisions waiting for the owner:

- Final review of completed T14, after the remaining acceptance work.


- 2026-10-15: Implementation commit 6bf1bc22 passed independent review
  with no must findings and one should finding, R10. Review
  20261015T143830Z-6bf1bc22 asks for a next step in the unsupported-default
  message. Added guidance to use a literal default or no default. The
  correction needs compilation and focused restriction checks before commit.

Decisions waiting for the owner:

- Final review of completed T14 after integration and installed acceptance.


- 2026-10-15: The R10 diagnostic correction compiles and all 33 restriction
  examples pass in 1.43 seconds. Recorded finding
  20261015T143830Z-6bf1bc22#1 as fixed. Evidence:
  build/t14-default-message-build-20261015.log and
  build/t14-default-message-check-20261015.log. The correction changes only
  diagnostic wording and now goes through its own independent review.

Decisions waiting for the owner:

- Final review of completed T14 after integration and installed acceptance.


- 2026-10-15: Diagnostic correction 8e646f05 passed independent review
  with no findings. Implementation 6bf1bc22 and its correction are accepted
  locally. The remaining work is main integration, the public default example,
  installed acceptance on both platforms and final owner review.

Decisions waiting for the owner:

- Final review of completed T14 after the remaining acceptance work.


- 2026-10-15: Fetched remote state and integrated main a2f480bd through
  PR 127 into the T14 working revision. The sandbox fetch could not resolve
  GitHub; the permitted network fetch succeeded and found no newer main.
  The only merge conflict was the core module count. Walking the actual public
  imports gives 72 modules, including main's join modules and T14's default
  modules; the package test now records 72. No conflicts remain. Judge code,
  claims, frozen corpora and the lock match main exactly.

  Runtime, conformance and checked-public-documentation builds are running
  with a 900-second limit in build/t14-joins-integrated-build-20261015.log.
  Prior test results do not establish acceptance of the integrated revision.
  Its model, package and protected-verdict checks remain necessary.

Decisions waiting for the owner:

- Final review of completed T14 after integration and installed acceptance.


- 2026-10-15: The integrated runtime, conformance runtime and checked
  public documentation build successfully. Outputs are retained at
  build/t14-joins-integrated, build/t14-joins-integrated-2 and
  build/t14-joins-integrated-3. Full model, standalone package/ownership and
  protected-verdict checks are running against these outputs. Their logs are
  build/t14-joins-integrated-model-20261015.log,
  build/t14-joins-integrated-package-20261015.log and
  build/t14-joins-integrated-verdict-20261015.log. Integration remains
  uncommitted until its checks pass.

Decisions waiting for the owner:

- Final review of completed T14 after installed acceptance.


- 2026-10-15: Integrated package validation passes all 13 tests in
  21.91 seconds, including the isolated package builds, import closure,
  ownership and frontend boundaries. The protected verdict passes, including
  all 20 corpus-v15 RIGHT/FULL cases. T14's previous agreement gains remain
  and no disagreement or harness error appears. The full 185-test model run
  remains active.

  Inspected the public example boundary for the next unit. The existing
  approved invoice contract requires an exactly nullable note column, so it
  cannot certify a NOT NULL DEFAULT note. The new example will use a separate
  contract and retain all existing approved examples. The installed CLI suite
  discovers cases through belay.toml; bundle and cache acceptance must also
  exercise the new case through the delivered project interfaces.

Decisions waiting for the owner:

- Final review of completed T14 after installed acceptance.


- 2026-10-15: The integrated full model suite passes all 185 tests in
  527.38 seconds, within the unchanged 600-second limit. This validates the
  combined default and RIGHT/FULL join interfaces, including all ten native
  ADD parameter groups. Together with the runtime/documentation builds,
  13 package/frontend checks and protected verdict, the integration is ready
  to commit and review. Main's protected judge files remain unchanged.

Decisions waiting for the owner:

- Final review of completed T14 after the public example and installed acceptance.


- 2026-10-15: Integration commit d83096eb passed independent review
  20261015T145625Z-d83096eb with no findings. The reviewer confirmed the
  72-module closure and conflict resolution. The integrated implementation
  is ready for the public NOT NULL DEFAULT example and installed acceptance.

Decisions waiting for the owner:

- Final review of completed T14 after the remaining acceptance work.


- 2026-10-15: Added examples/constant_default with a separate contract,
  baseline and proofs project. It adds priority INTEGER NOT NULL DEFAULT 7,
  preserves all invoice rowids and amounts, and requires successful execution
  for every admitted starting table. It uses the delivered generated target
  and project interfaces. Existing approved example files are unchanged.

  The public verify command returns VERIFIED after fixing the initial Lean
  layout and explicit reduction errors; failed runs are retained separately.
  Evidence: build/t14-constant-default-example3-20261015.log. The packaged
  runtime builds at build/t14-default-example. Added a bundle-suite test that
  changes DEFAULT 7 to DEFAULT 8 and checks both public gates reject the
  original certificate. Existing discovery covers the new positive CLI case
  and separate author/verifier caches, a warm verifier and no cache. These
  checks are running in build/t14-default-example-gates-20261015.log.

  The example remains uncommitted and has not passed independent review or
  offline installed acceptance. Its new baseline is part of the eventual
  owner-reviewed T14 change, not an update to an existing approval.

Decisions waiting for the owner:

- Final review of completed T14, including the new example contract and baseline.


- 2026-10-15: The new example passes all three public-gate scenarios in
  19.26 seconds: positive source verification; prepare followed by verification
  with an independent cold cache, warm cache and no cache; and rejection of
  DEFAULT 8 by both source and bundle gates when the contract requires 7.
  All 34 documentation, ownership, frontend and project-config checks pass
  in 2.11 seconds. Evidence: build/t14-default-example-gates-20261015.log
  and build/t14-default-example-source-checks-20261015.log.

  The example and its rejection test are ready for an implementation commit
  and independent review. These are packaged-runtime checks on macOS, not
  offline installed or Linux acceptance.

Decisions waiting for the owner:

- Final review of completed T14, including the example contract and baseline.


- 2026-10-15: Example commit 4403518d passed independent review with no
  must issues and two R13 should findings. Added the example and its baseline
  path to examples/README.md and its changed-default gate test to the
  docs/data-path.md test table. Also added the same pinned lean-toolchain file
  used by the other proofs projects, as the review observation suggested.

  All 28 documentation and project checks pass. The rebuilt runtime passes
  the separate-cache and no-cache scenario in 10.22 seconds with the explicit
  toolchain. Evidence: build/t14-default-example-doc-check-20261015.log,
  build/t14-default-example-complete-build-20261015.log and
  build/t14-default-example-toolchain-check-20261015.log. Both review findings
  are recorded as fixed. The correction now needs independent review.

Decisions waiting for the owner:

- Final T14 review after actual offline installed acceptance on both platforms.


- 2026-10-15: Correction 093ce798 passed independent review
  20261015T150859Z-093ce798 with no findings. The public default example
  and its gate checks are reviewed. Packaging the macOS runtime as an
  offline archive is active in build/t14-default-offline-archive-20261015.log,
  using the ordinary content-addressing and closure-verification path with
  a 1,200-second outer limit. Installed acceptance is not yet established.

Decisions waiting for the owner:

- Final T14 review after installed acceptance on both platforms.


- 2026-10-15: The macOS offline archive was built successfully. Content
  addressing took 58.46 seconds, closure export and verification 25.61 seconds,
  and compression 25.30 seconds. The archive and checksum are retained in
  build/t14-default-installed-darwin. The complete packaging log is
  build/t14-default-offline-archive-20261015.log.

  Free space fell to 7.4 GiB. Under existing cleanup authorization, Nix
  garbage collection removed 2,501 unreachable paths and freed 7,987.03 MiB.
  The deletion log is build/t14-post-archive-gc-20261015.log; the archive and
  evidence were retained. Space returned to about 12 GiB and the resource
  check passes. Actual archive installation and the three default scenarios
  are now running with --runtime-variant installed in
  build/t14-default-installed-darwin-check-20261015.log. No installed pass
  is claimed until this process finishes.

Decisions waiting for the owner:

- Final T14 review after installed acceptance on both platforms.


- 2026-10-15: The first actual macOS installation failed before all three
  selected scenarios. Nix 2.18.1 copied the archive's entries with dummy -x
  names under copy --all, then rejected the missing named Bash path. The
  archive narinfo contains the correct original path. Cleanup had removed
  that original path, exposing a failure that existing store contents could
  hide. Evidence: build/t14-default-installed-darwin-check-20261015.log.

  Changed install.sh to copy the runtime-path declared by the archive and
  its closure explicitly, retaining offline mode and signature checks. The
  installer path test now exports a unique test-owned runtime to a local
  cache, removes only that test-owned store path, and verifies installation
  under a path with spaces and URI-special bytes. Both installer tests pass
  in 1.81 seconds in build/t14-installer-root-regression-20261015.log. This
  corrects the repository installer; it does not count the failed full-runtime
  installation as accepted. Rebuilt-archive acceptance remains necessary.

  Read-only Linux readiness reports x86_64, Nix available and about 25 GiB
  free. Python is not on the login PATH; validation uses the pinned Nix
  development environment. No source transfer or Linux build has run yet.

Decisions waiting for the owner:

- Final T14 review after actual installed acceptance on both platforms.


- 2026-10-15: Installer correction 8f31b13c passed independent review
  20261015T151828Z-8f31b13c with no findings. Authorized garbage collection
  before the archive rebuild removed 10,494 unreachable paths and freed
  899.43 MiB; the log is build/t14-installer-rebuild-gc-20261015.log.
  The resource check passes. The macOS runtime rebuild is active in
  build/t14-fixed-installer-build-20261015.log.

  Prepared and transferred a tracked-source archive of 8f31b13c to vihren
  at /var/tmp/sqlite-verifier-t14-20261015.JWpxSi/source.tar.gz. Local and
  remote SHA-256 both equal
  123a56d4df463c0aef21fd9016969119eddb168ea1fc4cb7c84e037e928b6181.
  The archive excludes untracked outputs and the product repository. The
  Linux runtime, conformance and documentation build is active in the
  extracted source directory, using the pinned Nix environment and resource
  guard. Its log is source/build/t14-linux-build.log under that directory.
  No Linux validation result is claimed yet.

Decisions waiting for the owner:

- Final T14 review after actual installed acceptance on both platforms.


- 2026-10-15: The Linux runtime, conformance runtime and checked public
  documentation builds pass. The complete model suite is running with a
  900-second outer acceptance limit in source/build/t14-linux-model.log.
  This does not change a CI timeout. Linux offline packaging is also active
  in source/build/t14-linux-archive.log.

  The corrected macOS runtime builds at build/t14-fixed-installer. A new
  offline archive is being built in build/t14-fixed-installed-darwin; its log
  is build/t14-fixed-offline-archive-20261015.log. The previous failed archive
  and logs remain retained. Neither platform has passed installed acceptance
  yet.

Decisions waiting for the owner:

- Final T14 review after actual installed acceptance on both platforms.


- 2026-10-15: The corrected macOS offline archive is complete: content
  addressing 71.82 seconds, closure export/verification 28.66 seconds, and
  compression 24.09 seconds. Packaging reduced free space below the guard.
  Authorized garbage collection removed 77 unreachable paths and freed
  5,575.18 MiB; the full log is build/t14-fixed-archive-gc-20261015.log.
  The resource check then passed. Installed acceptance of the corrected
  archive is active in build/t14-fixed-installed-darwin-check-20261015.log.

  Linux offline packaging also passes: content addressing 87.58 seconds,
  closure export/verification 60.15 seconds and compression 27.80 seconds.
  The archive is source/build/t14-linux-installed/sqlite-verifier-x86_64-linux.tar.gz
  under /var/tmp/sqlite-verifier-t14-20261015.JWpxSi. With about 22 GiB free
  and a passing guard, its actual installed checks are running in
  source/build/t14-linux-installed-check.log. Linux full model and affected
  harness/frozen/package/installer regressions remain active in their own logs.

Decisions waiting for the owner:

- Final T14 review after actual installed acceptance on both platforms.


- 2026-10-15: Actual offline-installed acceptance passes on both platforms.
  macOS passes all three selected scenarios in 78.67 seconds; Linux passes
  them in 23.14 seconds. Each run extracts and installs its real archive into
  a fresh path containing spaces, Unicode and URI-special bytes, then uses
  its installed launcher. The scenarios verify the positive example, prepare
  with an independent author cache and verify with cold/warm verifier caches
  and no cache, and reject DEFAULT 8 through both gates with the original
  DEFAULT 7 contract and certificate. The failed first macOS installation
  remains retained separately and is not counted as a pass.

  Evidence: build/t14-fixed-installed-darwin-check-20261015.log and
  build/t14-linux-validation/t14-linux-installed-check.log. Linux full model
  and affected regressions are still running; final acceptance and owner
  review wait for those results.

Decisions waiting for the owner:

- Final T14 review after the remaining Linux regression results.


- 2026-10-15: Remote synchronization confirms PR 128 merged as 3875420d.
  The clean main workspace is updated. This task remains integrated through
  PR 127; the new corpus 16 claim still needs integration and verdict checks.
  Linux affected regressions pass 342 tests in 223.69 seconds, recorded in
  source/build/t14-linux-regressions.log on vihren under
  /var/tmp/sqlite-verifier-t14-20261015.JWpxSi. The full Linux model run
  remains active. Installed acceptance passed on both platforms as above.

Decisions waiting for the owner:

- Final T14 review after acceptance and a reviewable pull request.


- 2026-10-15: Linux full model acceptance passes all 185 tests in
  637.47 seconds. The model and regression logs are retained in
  build/t14-linux-validation and match their remote SHA-256 hashes.
  Integrated main 3875420d into the working change without conflicts.
  Judge and integrity files match main exactly. This integration has not
  passed its verdict or independent review yet.

  Authorized garbage collection deleted four unreachable store paths and
  freed 188.75 MiB. The log is build/t14-claim-integration-gc-20261015.log.
  About 4.7 GiB remains free, below the 10 GiB build threshold. Further
  expensive checks wait for targeted cleanup approval.

Decisions waiting for the owner:

- Targeted cleanup to restore build space.
- Final T14 review after integrated acceptance and a reviewable pull request.


- 2026-10-15: The owner approved the targeted cleanup. Removed the two
  completed test directories /private/tmp/nix-shell.X0sqxy and
  /private/tmp/nix-shell.1zPUTu. Deletions are recorded in
  build/t14-approved-test-cleanup-20261015.jsonl. Nix garbage collection
  removed 54 unreachable store paths and freed 4,554.41 MiB; its log is
  build/t14-approved-test-gc-20261015.log. About 11 GiB is now free and
  the resource check passes. Test logs and runtime archives are retained.

Decisions waiting for the owner:

- Final T14 review after integrated acceptance and a reviewable pull request.


- 2026-10-15: The integrated corpus 16 verdict passes on macOS. All
  26 new cases agree; no corpus reports DISAGREE or HARNESS_ERROR.
  The result is build/t14-corpus16-verdict/counts.json and the build log is
  build/t14-corpus16-verdict-20261015.log. The judge and integrity files
  remain identical to main 3875420d. Production code is unchanged from
  the revision accepted by the Linux and installed checks above.

Decisions waiting for the owner:

- Final T14 review after the integration review and hosted CI.


- 2026-10-15: Draft PR 130 is open at 6e826ccd. Hosted Verdict passes.
  Hosted Linux CI found one stale obligation-inventory entry: add-column-plain
  still pointed to column.plain after T14 replaced it with readDefaultValue.
  Renamed the entry to add-column-default-readback and bound it to the actual
  admission check. Its existing add-column-constraint coverage still applies,
  because resolution refuses failed default readback before execution.

  The complete source suite passes 521 tests and 58 subtests in 42.17 seconds
  with two Linux-only pidfd checks skipped on macOS. The passing log is
  build/t14-source-ci-fix-full-runtime-20261015.log. Two earlier local commands
  selected incomplete runtime roots; their setup failures are retained in
  separate logs and are not counted as passes. This correction changes only
  the obligation inventory, not production semantics or protected judge inputs.

Decisions waiting for the owner:

- Final T14 review after the corrected hosted CI run.


- 2026-10-15: The second hosted run of PR 130 passed Verdict and source
  checks, then failed 22 kernel tests because their shared structural record
  still declared version 2. The codec requires version 3 after the default
  syntax change, so these tests stopped before their intended attack checks.
  Updated tests/kernel_gate_support.py to the current version. The complete
  sandboxed kernel suite now passes all 33 tests in
  build/t14-kernel-record3-20261015.log. This changes the test fixture only;
  production codec and gate behavior are unchanged. Independent review and
  a fresh hosted run are required before claiming CI acceptance.

Decisions waiting for the owner:

- Final review of PR 130 after corrected hosted CI.
