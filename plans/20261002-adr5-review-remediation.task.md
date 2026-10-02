# ADR 0005: repair upstream coverage and reporting

Created 2026-10-02. Status: IN PROGRESS.
Status: [progress](20261002-adr5-review-remediation.status.md).
Specs: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md), especially
§1.3–1.4, §3.2–3.6 and the two readiness gates.
Owner authorization, 2026-10-02: fix the review findings using the workspace
process, with at least one separate task. This task precedes implementation.

## Observable outcomes

The new generic corpus accounts for the pinned upstream file families relevant
to the ADR's feature table. Its explicit source catalog includes every file
from the selected families, with a recorded reason for each file excluded by
the ADR's non-goals. The catalog cannot silently substitute one representative
file for a family. Sources, selection policy, profiles, every runtime candidate,
exclusions and final accepted membership are bound to the frozen artifact.
Changing the catalog or policy creates corpus v5; frozen v1–v4 remain unchanged.

Eligible foreign-key cases run under an established, verified foreign-key-on
profile when their source execution requires it. Clock-dependent cases use the
existing controlled native clock. Profile changes, unsupported settings and
unreconstructable contexts remain explicit exclusions. The resulting evidence
includes successful cascading deletes, deferred/transactional constraints,
controlled date/time expressions, CAST to REAL, numeric arithmetic and the
workload-relevant query/aggregate features. Source-by-source and profile-by-
profile before/after tables report actual yield and each remaining blocker.
A file with zero cases is an explicit coverage gap, never claimed as coverage.

The Tcl/native fidelity check reproduces Tcl's REAL and BLOB result semantics
without changing native typed observations, SQL or expected results. Faithful
cases such as CAST of numeric text can be acquired; materially changed values,
side-effecting callbacks and unsupported parameter bindings are still refused.
A declared round-trip Tcl display-precision condition may be used for new
acquisition. The pinned tester's original precision remains part of the source
record; source SQL and original expected strings are unchanged. Any original
assertion that fails under the declared condition, later precision change or
unobserved precision is explicitly refused. The acquisition condition and
observed precision are bound to the source/profile policy and frozen artifact;
rounded legacy Tcl strings cannot prove exact REAL correspondence.

Registered functions affect eligibility only when a case's SQL or its retained
prefix depends on them. Any restored connection/attachment context must meet
ADR §3.4's faithful-prefix or verified-state condition. This task does not admit
multi-database or arbitrary Tcl callback semantics by assumption.

Reports distinguish source-file labels from measured per-case coverage. No
field or displayed count presents all cases in a labelled file as executions of
that feature. Authored labels, source provenance and genuine SQL observations
retain their separate meanings; historical reports remain readable and clearly
historical. Expression sampling reports both selected candidates and actual
accepted yield, including inactive cohorts and their blockers.

Public profile documentation describes generic capabilities and independent
native builds. It does not publish private driver measurements or present
internal agent review as an owner decision. Native comparison infrastructure
and production profile authorization remain distinct. Supported defaults and
model admission do not change as part of this repair.

Fresh native replay passes for the complete v5 corpus on both supported native
platforms. Current and retained corpus storage stay within ADR budgets; ordinary
development replay remains bounded and full CI checks remain intact. Progress
reports bind the new generic corpus and current runtime/frontend/harness bytes.
External workload baselines are refreshed against that same final v5 artifact
in the private product repository, with private cases counted once logically.
The suite gate stays open until these repairs and both-platform checks pass.
No production semantic-model extension or C8 mutant claim is included.

## Behavioral verification

Catalog checks compare the explicit inventory against all matching files in
the pinned source archive and verify exclusion reasons, source digests and
complete runtime accounting. Real Tcl extraction tests recover representative
foreign-key cascade, date/time, REAL/BLOB and unrelated registered-function
cases. Paired negative cases reject wrong results, changed profiles/clocks,
callback side effects, unbound variables and unverifiable attached contexts.

Report checks distinguish source labels from actual tested features and keep
all inactive sampling cohorts visible. A fresh complete extraction, retained
fidelity ledger and freeze verify all accepted cases; there is no per-file cap
or guessed yield target. Native replay on macOS arm64 and Linux amd64, legacy
compatibility, corpus size checks, bounded development tests and full model/
upstream checks establish completion. Document links and generic/private source
boundaries are checked. Every command and test has a configured timeout.

## Tricky points and existing sources

`upstream_catalog.py` currently fixes 55 files and attaches source labels to
cases. `upstream_sampling.py` selects runtime identities before acceptance;
selection counts do not establish coverage. `upstream_proxy.tcl`,
`upstream_assertions.py`, `upstream_helpers.py`, `upstream_fidelity.py` and
`upstream_selection.py` govern source execution and native comparison.
Extraction must preserve every refusal and first-error boundary.

`freeze_validation.py` binds the current catalog, extractor bytes and fidelity
ledger. `freeze_corpus.py`, `corpus_shards.py`, `corpus_evidence.py` and progress/
development sampling currently refer to v4. Add the new version without
rewriting retained observations or assuming that cases from two different
profiles are interchangeable. The extra 3.53.4 native build is comparison
infrastructure; its existence does not authorize a production profile.

The private workload already has independent source-bound native evidence on
both scoped platforms. Its existing v4 baselines are historical evidence while
the generic repair is open. Workload SQL, identities, measurements and refreshed
baselines stay outside this public repository.
