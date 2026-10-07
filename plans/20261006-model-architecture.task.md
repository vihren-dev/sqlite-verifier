# SQLite model boundary and execution architecture

Created 2026-10-06. Status: DONE on 2026-10-07.
Status file: [status](20261006-model-architecture.status.md).
ADR: [accepted decision](../docs/adr-0006-model-boundary-and-execution-levels.md).
Sources: public [issue #23](https://github.com/vihren-dev/sqlite-verifier/issues/23)
and [issue #31](https://github.com/vihren-dev/sqlite-verifier/issues/31).

## Observable behavior when done

A public ADR records the decision accepted by the owner on 2026-10-07. It
specifies a separate Lake
package for `Belay.Sqlite`, required by the root application as a path
dependency. An isolated model build rejects application imports. The core
model has no `Lean` dependency; its separate structural codec can use `Lean`.
A separate Python SQL frontend uses `belay.sqlite`, with a namespace directory
`belay/` that has no `__init__.py` and contains only `sqlite/` initially. It
produces structural records, while generation
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
review follows `docs/review-checklist.md`. The namespace contract and accepted
date match the owner's change to PR44. The updated accepted ADR is delivered on
that pull request after current main integration and validation. Package and
execution implementation have separate acceptance checks.
No build is claimed as proof of a future package boundary.

## Delivered decision

The owner-accepted namespace amendment was delivered through
[PR44](https://github.com/vihren-dev/sqlite-verifier/pull/44) by normal merge
`b91e5cb5b3e145bc9713cc5e2b88bd502aa9ad0a` on 2026-10-07 at 08:03:17 UTC.
The exact reviewed head `9458fc52d7d79f4b003e4535f77cf002eb43c7c2` passed both
native CI checks and all three protected-baseline checks. The status file
records their exact identities. T09 is DONE; issues #23 and #31 remain open
for implementation. T10 planning is separate, and its code remains held for
repository delivery of the approved exporter and executor changes in PR47/48.

## Relevant code and constraints

`lakefile.toml` currently groups model and application libraries in one package.
`packages/belay-sqlite/Belay/Sqlite/SqlExecution.lean` owns `ProfileExecutes` and the current
connection/script behavior. `packages/belay-sqlite/Belay/Sqlite/Codec.lean` imports `Lean`.
`build-support/sources.nix`, `default.nix` and `runtime.nix` select, build and
install artifacts. `migration_check/runtime.py`, `source_closure.py`,
`prepare.py` and `bundle.py` resolve trusted modules and proof inputs.

`Conforms` currently calls both `Schema.lookup` and `Schema.lookupProperties`.
Those structural operations must remain available in the model during the
package split. Application convenience helpers can move independently. The
later table-shape change does not become a prerequisite of that split.
