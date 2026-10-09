# ADR 0009: Build the Lean core documentation of the API reference once per toolchain

Date: 2026-10-09. Status: DRAFT. The owner chose the decision below; the open
questions must be answered before this ADR is proposed.
Audience: designers and reviewers.
Related: [API reference](api-reference.md), [CI](ci.md),
[task for PR #63](../plans/20261008-ci-time-docs-scope-and-cached-reference.task.md).

## Context

The checked API reference is built by `build-support/api-reference.nix`
(`apiReferenceBase`) and completed with the commit hash by
`build-support/api-reference-links.nix` (`apiReference`). PR #63 removed the
commit hash from the expensive build, so Nix reuses it when the Lean sources
do not change. A pull request that changes a Lean source still runs the full
base build.

`tools/api_reference.py` drives doc-gen4 through one database,
`api-docs.db`:

1. `bibPrepass` prepares the bibliography; the project has none.
2. `genCore Init` and `genCore Std` add Lean's own libraries, so that our
   pages can link to core types.
3. `single` adds each of the 24 public modules, with its source link.
4. `fromDb` writes all HTML pages: 1,170 pages, 172 MB.
5. Python corrects known generator links and checks every local link.

Measured on macOS arm64, 2026-10-09, with the base build's commands outside
Nix:

| Stage | Time | Depends on our sources |
| --- | --- | --- |
| `lake build SqliteVerifier` | 7 s | yes |
| Documentation inventory | 6 s | yes |
| `bibPrepass` | 0.5 s | no |
| `genCore Init` | 35 s | no |
| `genCore Std` | 114 s | no |
| `single`, 24 modules | 17 s | yes |
| `fromDb` | 9 s | yes |
| Python link correction | 79 s | all pages |
| Python link check | 79 s | all pages |
| Total | about 346 s | |

The database is 97 MB after the build. On CI, PR #63's run spent 379 s in
the base build phase, which agrees with these measurements. Building doc-gen4
itself takes 92 s locally; PR #63 keeps it in the CI cache.

About 150 s, the `bibPrepass` and `genCore` stages, depend only on the Lean
toolchain and doc-gen4. They run again for each change to a Lean source.

## Decision

A new Nix derivation, `apiReferenceCore`, runs `bibPrepass`, `genCore Init`
and `genCore Std`, and stores the resulting database. Its inputs are the Lean
toolchain and the pinned doc-gen4, and nothing from the repository's sources.
Nix and the CI cache therefore reuse it until the toolchain or doc-gen4
changes.

`apiReferenceBase` copies that database, runs `single` for each public module
and `fromDb`, and keeps its existing checks. `tools/ci_store_gc.py` keeps
`apiReferenceCore` in the saved cache.

The published reference stays the same: the same pages, source links, link
corrections and checks.

## Expected effect

A pull request that changes a Lean source no longer runs the about 150 s of
core documentation. Measured from the table, its base build drops from about
346 s to about 196 s. The Python link passes, about 158 s, stay; see "Not
decided here".

## Open questions

These must be answered, with evidence, before this ADR is proposed.

1. **Same output.** Does a reference built from a copied core database give the
   same pages, byte for byte, as today's build in one database?
2. **Database reuse.** Can `single` and `fromDb` write to a copy of the core
   database without other state from the `genCore` run? Does doc-gen4 store
   paths or build directories in the database, which would differ after the
   copy?
3. **No project input.** Today `genCore` runs as `lake env doc-gen4 ...` in our
   project root. Does it read anything from the project, such as the Lake
   environment or `LEAN_PATH`, or does it need only the toolchain? Can it run
   in an empty project?
4. **Cache size.** How large is the core database, compressed? The CI cache and
   the Attic cache must hold it.
5. **Core pages.** `fromDb` writes the core pages again in each build. Is that
   part of the 9 s small enough, or should the core derivation also store its
   pages?
6. **Toolchain upgrades.** Lean upgrades follow each stable release within two
   weeks. Each upgrade rebuilds the core database once. Confirm that nothing
   else invalidates it, such as a change to `tools/api_reference.py`.

## Not decided here

- **The Python link passes.** They parse all 1,170 pages twice, although only
  25 are ours. Checking the core pages once in the core derivation, or parsing
  each page once, would save up to about 150 s more. This is a separate
  decision.
- **The doc-gen4 build.** It is already cached by PR #63.

## Alternatives considered

**Leave the build as it is after PR #63.** Rejected. Pull requests that change
Lean sources are the main development work, and each one would keep paying
for the core documentation.

**Build the reference only on `main`.** Rejected by the owner on 2026-10-08,
when option A of PR #63 kept the reference check on pull requests.
