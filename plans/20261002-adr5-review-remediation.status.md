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
anonymous driver-setting summary is unnecessary and will be replaced with
neutral capability requirements. Internal agent review is not owner approval.

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
