# ADR 0009: Build the core API reference once per toolchain, and check only our pages

Date: 2026-10-09. Status: PROPOSED.
Audience: designers and reviewers.
Related: [API reference](api-reference.md), [CI](ci.md),
[task for PR #63](../plans/20261008-ci-time-docs-scope-and-cached-reference.task.md),
"Testing" in [AGENTS.md](../AGENTS.md).

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
5. `correct_reference_links` rewrites two known kinds of broken doc-gen4
   links, and `validate_reference` checks module pages, source links and every
   local link and anchor.

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
| `correct_reference_links` | 79 s | parses all pages |
| `validate_reference` | 79 s | parses all pages |
| Total | about 346 s | |

On CI, PR #63's run spent 379 s in the base build phase, which agrees.

Two parts do not depend on our sources:

- The core documentation, about 150 s, depends only on the Lean toolchain and
  doc-gen4.
- The two Python passes parse all 1,170 pages, but only 24 pages are ours. The
  other 1,146 pages contain 826,137 of the 829,888 local links. Checking them
  tests doc-gen4 and Lean's own documentation, not our code. The testing rules
  in `AGENTS.md` exclude tests of a dependency's own behavior.

## Decision

### 1. A separate core documentation build

A new Nix derivation, `apiReferenceCore`, runs `bibPrepass`, `genCore Init`
and `genCore Std` in an empty directory, and stores the resulting build
directory with `api-docs.db`. Its inputs are the Lean toolchain and the pinned
doc-gen4 only. Its commands are in the Nix file, not in a repository script, so
a change to the repository's tools does not rebuild it. Nix and the CI cache
reuse it until the toolchain or doc-gen4 changes.

`apiReferenceBase` copies that build directory, runs `single` for each public
module and `fromDb`, and then runs the checks of decision 2.
`tools/ci_store_gc.py` keeps `apiReferenceCore` in the saved cache.

### 2. Checks of our pages only

The reference build checks our pages, not the pages that doc-gen4 writes for
Lean's libraries:

- **Module pages.** Each public module has a page. This stays as it is.
- **Source links.** Each public declaration links to its file at the
  placeholder or commit. This stays as it is.
- **Local links and anchors.** Every local link on our 24 pages resolves, and
  its anchor exists, also when the target is a Lean library page. Links on
  Lean's library pages are not checked.
- **Link corrections.** The recursor-link correction applies to our pages. The
  correction of Lean's own `Init/Tactic.html` typo is removed: the typo is
  only on Lean's library pages. The recursor-link bug is reported to doc-gen4,
  and the correction names that report.

The source-link and module-page checks test our build code. The link and
anchor checks test how doc-gen4 renders our declarations, which changes with
our code.

## Evidence

Each question was answered on macOS arm64 on 2026-10-09:

| Question | Answer |
| --- | --- |
| Does a build from a copied core database give the same reference? | Yes. All 1,186 files match the build in one database, byte for byte. |
| Does the core database contain paths of its build? | No. No row contains the build directory, `/nix/store`, `/Users/` or `/private/tmp`. |
| Does `genCore` need our project? | No. It ran in an empty directory, without `lake env`, in the same time. |
| How large is the core database? | 95 MB, 13.2 MB with zstd level 3. |
| Should the core build also store its pages? | No. `fromDb` writes all 1,170 pages in 8.6 s. |
| Do our pages need the recursor-link correction? | Yes. Of the 178 corrections, 3 files are ours and 46 are Lean's. |
| What do the checks of decision 2 cost? | Parsing our 24 pages and the 27 Lean pages they link to took 1.0 s, against 158 s for all pages. |

## Expected effect

A pull request that changes a Lean source runs the Lean build, the inventory,
`single`, `fromDb` and the checks of our pages: about 7 + 6 + 17 + 9 + 2 s,
about 41 s instead of about 346 s. A pull request that does not change Lean
sources still reuses the whole base build, as after PR #63. A Lean toolchain
or doc-gen4 upgrade rebuilds the core documentation once, about 150 s.

The saved cache grows by about 13 MB compressed for each platform.

## Consequences

- The published reference keeps all 1,170 pages. Lean's library pages can
  contain broken links that the build no longer reports. Those links come from
  doc-gen4 or Lean, and the reference is not hosted yet.
- The `reference-check.json` report counts the links on our pages only.
- [API reference](api-reference.md) describes the narrower checks.
- The requirements of the checked API reference task (issue #26) become
  narrower: the owner decides this with this ADR.

## Alternatives considered

**Leave the build as it is after PR #63.** Rejected. Pull requests that change
Lean sources are the main development work, and each one would keep paying
for the core documentation and the checks of Lean's pages.

**Check Lean's pages once in the core derivation.** Rejected. It would keep a
test of a dependency's own output, which the testing rules exclude, and it
would make the core derivation fail on problems that only doc-gen4 or Lean can
fix.

**Build the reference only on `main`.** Rejected by the owner on 2026-10-08,
when option A of PR #63 kept the reference check on pull requests.
