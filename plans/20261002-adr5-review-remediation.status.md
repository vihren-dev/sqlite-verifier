# ADR 0005 review repair status

Created 2026-10-02. Status: IN PROGRESS.
Task: [coverage and reporting repair](20261002-adr5-review-remediation.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

The owner requested fixes after a review found narrow upstream family
selection, low yields for required features, misleading source-label counts,
Tcl/native REAL/BLOB fidelity limits and ambiguous public driver-profile prose.
The existing v4 artifact and measurements remain historical and unchanged.
The workload-suite gate is open; semantic-model development has not started.

Independent review confirms that the accepted ADR already authorizes generic
profile recording capabilities. The additional native pin is optional
comparison infrastructure, not a production profile decision. The public task's
anonymous driver-setting summary has been replaced with neutral capability
requirements. Internal agent review is not owner approval.

## Progress

- 2026-10-02: Read the owner's review and explicit fix authorization, the ADR,
  current catalog/freeze validation and the document refactoring process.
  Prepared this outcome-based task/status pair before implementation. Parallel
  read-only investigations cover fidelity, profile-aware yield and reporting.
  The separately authorized Linux private evidence commands can finish;
  completion will not be claimed against the superseded generic baseline.

- 2026-10-02: Replaced combined feature counts in current progress with
  separate case, source-file and unscoped scenario-label views. New manifest
  label declarations are validated; historical v4 metadata remains readable
  and unchanged. The JSON labels split into 219 upstream file labels and one
  authored case label, rather than 220 executions of each function. Public
  profile task prose now states generic capabilities and distinguishes internal
  review from owner approval. Bounded reporting/evidence/document checks pass:
  34 tests in 14.28 seconds, including complete v4 loading and all requirement
  rows. Catalogue expansion, extraction repair and v5 freeze remain open.

- 2026-10-02: Pinned `tester.tcl` sets display precision 15, so its REAL strings
  cannot establish exact bits generally. Specified an explicit round-trip
  acquisition condition before implementation, retaining original source and
  expected strings and refusing failed expectations or changed/unobserved
  precision. This is capture formatting, not a new SQLite production profile.
  Native typed observations remain unchanged. Independent inventory audit
  verifies all 171 sources; `delete_db.test` has an explicit file-level exclusion.
  Existing cascade and clock cases are substantive; the actual authored gaps
  are deferred-FK commit outcomes and non-NULL CAST-to-REAL.

- 2026-10-02: Added three neutral authored boundaries for deferred foreign-key
  repair/commit, failed deferred COMMIT with its open transaction and persisted
  state, and numeric-prefix CAST-to-REAL plus arithmetic. Fresh native capture,
  shard loading/replay and a corrupted REAL-bit refusal pass (3 tests in 0.57
  seconds). Existing 43-case and 23-case catalogs and v1–v4 artifacts are
  unchanged. The repaired freeze will include 69 authored cases; no new model
  admission is claimed.

- 2026-10-02: Expanded the exact pinned catalog from 55 to 171 sources,
  accounting for all 21 declared families and 28 explicit file exclusions.
  Catalog acquisition routes through measured FK/clock profiles and declared
  round-trip Tcl precision. Unused registrations no longer block unrelated SQL;
  direct, operator, view, trigger and partial-DDL callback dependencies remain
  refusals. REAL comparison verifies exact native bits and BLOB comparison
  preserves all bytes. The unchanged CAST source records 100/134 assertions,
  including 27 cases with REAL cells and five with BLOB cells; fresh replay
  passes. Date precision changes and foreign-key setting changes remain named
  limitations, without changing source expectations.

  New v5 freezing includes the 69 authored definitions, scoped label counts,
  all retained v1–v4 byte accounting and complete harness bindings. The same
  stateless retained-policy boundary protects ordinary v5 loading: every case
  must match its accepted source identity, hash, labels, profile, clock and
  observed precision. Fully rebound semantic corruptions are refused; future
  current-policy changes do not invalidate historical evidence. Bounded combined
  freeze/evidence/acquisition checks pass (84 in 6.44 seconds), the isolated
  upstream target passes (54 in 2.16 seconds), and full historical model checks
  pass (285 plus one upstream-owned Tcl skip in 210.17 seconds). The retained
  boundary's subsequent focused checks pass (31 in 1.07 seconds). The complete
  uncapped extraction, fidelity ledger, actual v5 freeze, both-platform replay
  and refreshed private baselines remain open. No semantic-model code changed.

- 2026-10-02: The complete diagnostic scan finished 171 sources, including 143
  runnable sources and 28 explicit file exclusions: 153,764 runtime assertions
  and 4,257 upstream cases, with no timeout or incomplete source. Independent
  native reconstruction reproduced all 325 fidelity refusals and established
  their causes. This capture is superseded and will not be frozen: it exposed
  an untracked database deletion/reopen boundary and missed registered JSON
  operator dependencies. The suspect original deletion case was already refused
  by the size gate; the admission audit found no accepted primary-file deletion
  association. A real small regression now checks the boundary directly.

  Native Tcl file-operation traces refuse mutations of the primary database,
  its sidecars and ancestor directories, including aliases, copying, renaming,
  writable channels and explicit timestamps. Unrelated cleanup and ordinary
  close/reopen remain eligible; a valid reset clears the refusal. Registered
  `->` and `->>` overrides are excluded even when their visible result matches
  the builtin. Actual per-call NULL display markers now recover custom Tcl
  rendering without changing native typed cells; missing markers, wrong values
  and empty-result/helper boundaries are checked. Accepted marker summaries are
  bound to source instances and successful-call precision counts. All Tcl helper
  bytes are included in freeze identities. Bounded provenance checks pass (88
  in 5.70 seconds), and the isolated actual upstream target passes (58 in 2.11
  seconds). A fresh complete capture, freeze and both-platform final baselines
  remain required. Historical corpora and model semantics are unchanged.

- 2026-10-02: The authoritative unchanged-extractor capture completed all 143
  runnable sources and 28 explicit exclusions from the 171-file catalog,
  accounting for 153,764 runtime assertions and 4,307 upstream cases. Every
  remaining fidelity refusal was independently reproduced and named: 264
  testfixture-extension or physical EXPLAIN observations, with retained proof
  bytes and zero unmapped causes. The source/profile before/after report keeps
  all 57 expression cohorts visible (one active, 56 inactive) and every zero-yield
  source explicit. Three used profile routes yield 3,322 default, 609 controlled-
  clock and 376 FK-on cases; the fourth declared route has no selected sources.
  These are profile/source yields, not executions of individual SQL features.

  Fresh full native replay and ordinary frozen loading pass for v5: 4,376 cases
  (4,307 upstream plus 69 authored) in 109 shards. Its directory is 8,694,264
  bytes; retaining v1–v5 uses 12,235,391 bytes. The maximum expanded case is
  999,167 bytes. All 40 historical artifact hashes remain unchanged.
  Cases digest: `663e38016b574c8436c2bb0d53ff9e356fde51b458c1640a4a99553f11fe98b4`.
  Manifest digest: `e9a965f05ec70f45af83b43f62a0ff7b19f5095f03bb53b0b7b7a64b73f3e082`.
  The capture remains bound to the exact `6ae554cc` extractor. Default replay
  activation, the separately reproduced out-of-catalog hardlink alias guard,
  final both-platform measurements and private v5 baselines remain open.

- 2026-10-02: Closed the separately reproduced hardlink alias gap after freezing
  the acquired scope. Creating a link from the primary database is now refused
  before a writable alias can change its unrecorded state. One shared guard and
  a real Tcl alias/write regression cover the failure. The acquired 171 sources
  and their Tcl helpers contain no link operation; exact original v5 capture
  provenance and all frozen bytes remain unchanged. The isolated upstream target
  passes all 58 checks in 1.98 seconds. Replay-default activation and final
  platform/workload baselines remain open.

- 2026-10-05: Activated v5 defaults in the progress command, development tier,
  just recipes and isolated Nix inputs, retaining explicit v4 compatibility and
  its original 100-case tier. Selection still uses all authored/synthetic cases
  and the unchanged source/name identity policy: v5 selects 184 cases. Actual
  v4/v5 partitions, all 3,500 requirement rows, runtime/source bindings and
  historical tier replay pass (14 checks in 139.39 seconds). The isolated v5
  sample passes 12 checks in 49.56 seconds, with its fresh CLI phase at 49.46
  seconds under the unchanged 60-second limit. Nix input/dependency checks pass
  (28 in 91.07 seconds). Full progress has a configured 420-second deadline.
  Final Linux measurements, full isolated model checks and refreshed private
  baselines remain open; model semantics and frozen observations are unchanged.

- 2026-10-05: Retained actual final macOS ARM64 execution receipts, the executed
  validator and its 722-file source snapshot, all bound to `fe116b87`. Complete
  native replay passes all 4,376 cases in 128.27 seconds. The 184-case development
  sample measures 37.21 seconds under its unchanged 60-second deadline. Full
  progress records 4,376 MODEL_UNSUPPORTED, 129 represented requirement rows and
  zero disagreements or harness errors. Before/after source, runtime, native and
  input bindings match; all three report hashes are verified. The first Linux
  full-native run timed out after 420.16 seconds without a completed success
  report. Its failed receipt and unchanged post-timeout bindings are retained,
  rather than claimed as a passing gate. Linux completion, full isolated model
  checks and refreshed external baselines remain open.

- 2026-10-05: Final post-v5 isolated model verification passes 322 tests with
  one expected Tcl-capture check delegated to the separate upstream target,
  in 350.278 seconds under the configured 420-second suite limit. Retained
  real JUnit, build log, derivation/output identity and 446 unchanged before/after
  source bindings establish the run. Linux's independent development sample
  passes in 56.58 seconds (57.42 seconds for the child command), with identical
  macOS selection identities and 184 MODEL_UNSUPPORTED results. Its successful
  receipt/report bytes were downloaded and verified after owner renewal of
  transfer approval. The full Linux native attempt and progress report remain
  uncompleted gates; external workload baseline closure is still pending.

- 2026-10-05: The second Linux full-native attempt also times out at 900.17
  seconds (exit 124), with unchanged source/runtime/native/input bindings and
  no completed native success report. Its failed receipt is retained separately.
  A dropped SSH transport was recovered to inspect the real result; no duplicate
  native job or private baseline was started. Full native replay remains an open
  gate while bounded filesystem/temporary-fixture diagnostics examine the cost.
  Corrected the progress document to show current v5 and 184-case samples first,
  keep v4/v3 evidence explicitly historical, and accurately retain these open
  gates. Source catalog command guidance and retained-version wording are also
  current. Bounded local Markdown destination checks pass.

- 2026-10-05: Final exact-current-code verification closes the model suite's
  expected Tcl omission: the isolated upstream target passes all 58 checks in
  2.813 seconds, including actual source observations. Final host checks pass
  286 tests plus 28 subtests in 37.911 seconds. Their resource guards and
  before/after source/document/runtime bindings pass; actual logs, JUnit,
  source snapshots and verification summaries are retained. The first host
  attempt selected the test-only runtime without examples and encountered a
  sandbox process-group restriction. Its failure evidence is preserved; the
  successful retry used the existing full runtime and approved execution scope.
  No code changed. Linux full-native replay and external baseline closure
  remain open; the independently successful Linux progress report awaits
  final retained evidence integration.
