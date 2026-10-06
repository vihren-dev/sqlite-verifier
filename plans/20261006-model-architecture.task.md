# SQLite model boundary and execution architecture

Created 2026-10-06. Status: AWAITING OWNER ACCEPTANCE.
Status file: [status](20261006-model-architecture.status.md).
ADR: [proposed decision](../docs/adr-0006-model-boundary-and-execution-levels.md).
Sources: public [issue #23](https://github.com/vihren-dev/sqlite-verifier/issues/23)
and [issue #31](https://github.com/vihren-dev/sqlite-verifier/issues/31).

## Observable behavior when done

A public ADR is ready for owner acceptance. It specifies a separate Lake
package for `Belay.Sqlite`, required by the root application as a path
dependency. An isolated model build rejects application imports. The core
model has no `Lean` dependency; its separate structural codec can use `Lean`.
A separate Python SQL frontend produces structural records, while generation
of application declarations stays outside it.

The ADR assigns semantic levels and exhaustive schema, data and transaction
statement categories. Each category owns its domain and effect; the connection
level owns statement atomicity, a common data constraint check owns constraint
validation, and the script level owns positions and stopping at the first error.
`ProfileExecutes` and the existing outcomes keep their meaning.

The decision covers model and application theorem ownership, structural schema
lookup ownership, Nix source/build boundaries, runtime package paths, offline
installed imports, and the trusted package closure used by the replacement
exporter. It describes acceptance evidence for later implementation. It does
not add SQL features, change CLI names or claim new conformance coverage.

## Acceptance checks

Check the architecture against the current Lake configuration, import graph,
execution relations, structural record codecs, Nix source sets and runtime
installation paths. Every local source reference resolves. The independent
review follows `docs/review-checklist.md`. The ADR remains proposed until the
owner accepts it; this task remains awaiting acceptance after review passes.
No build is claimed as proof of a future package boundary.

## Relevant code and constraints

`lakefile.toml` currently groups model and application libraries in one package.
`SqliteVerifier/SqlExecution.lean` owns `ProfileExecutes` and the current
connection/script behavior. `StructuralCodec.lean` imports `Lean`.
`build-support/sources.nix`, `default.nix` and `runtime.nix` select, build and
install artifacts. `migration_check/runtime.py`, `source_closure.py`,
`prepare.py` and `bundle.py` resolve trusted modules and proof inputs.

`Conforms` currently calls both `Schema.lookup` and `Schema.lookupProperties`.
Those structural operations must remain available in the model during the
package split. Application convenience helpers can move independently. The
later table-shape change does not become a prerequisite of that split.
