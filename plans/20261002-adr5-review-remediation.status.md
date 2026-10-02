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
