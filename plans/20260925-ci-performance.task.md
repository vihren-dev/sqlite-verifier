# Reduce complete CI elapsed time

Created: 2026-09-25. Status: ACTIVE.

## Required outcome

Complete Linux and macOS CI retains every source, independent kernel, native/model,
and installed-runtime case while doing less avoidable work. Protected baseline
drift rejects before module compilation using the exact source snapshots that
would be compiled. Matching inputs and optional baseline/schema-pin behavior
remain supported. Baseline mismatch takes precedence over later elaboration errors;
header discovery still precedes comparison and can fail first.

Independent suites may overlap with bounded concurrency after shared prerequisites,
with complete logs, unchanged per-suite deadlines, all children awaited, and any
failure propagated. Only immutable Nix dependencies may be reused across CI runs;
source proof checks and acceptance verdicts remain fresh. Package timings expose
copying, export, signature checks, compression, installation and installed cases.

## Observable validation

Focused regression tests demonstrate early rejection, closure completeness,
snapshot consistency and matching-input compilation plus kernel verification.
Concurrency checks demonstrate overlap, failure propagation and awaited children.
All existing checks and offline archive installation run on both platforms.
Repeated full-package runs of the same revision measure end-to-end elapsed time,
separating cold and warm dependency cache results. Retain concurrency and caching
only when the evidence supports them. Documentation routing, release protection,
signature verification and archive size limits remain in force.

## Context and constraints

Requested report: ../reports/20260925-sqlite-verifier-ci-performance.md (outside
this repository). Baseline run36138251243: macOS23m28s, Linux18m33s. Relevant files:
migration_check/{cli,compile,baseline,source_closure}.py, justfile,
.github/workflows/ci.yml, packaging/build_runtime.py, tests/runtime_package_test.py,
and docs/ci.md. Use small path:./nix inputs, resource checks and existing test
isolation. Do not cache proof verdicts or weaken any trust boundary. v0.1.0 is
already tagged and its running publication workflow must retain its immutable tag.
