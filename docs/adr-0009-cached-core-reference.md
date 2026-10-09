# ADR 0009: Build the core API reference once per toolchain, without checks of doc-gen4

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
  other 1,146 pages contain 826,137 of the 829,888 local links.

`validate_reference` tests doc-gen4, also on our pages. It takes the expected
modules from the same function that selects the modules for doc-gen4, and the
expected source-link prefix from the same formula that builds the source URI.
So it can fail only when doc-gen4 does not write what we passed to it. The link
and anchor checks test how doc-gen4 renders links.

The task record of the reference
([status](../plans/20261006-checked-api-reference.status.md)) lists what these
checks found: two errors in the validator itself, links from doc-gen4 to
generated recursors that have no anchor, and a typo in Lean's own
documentation. Since then, every recorded run gave the same 178 corrections and
no new failure. The testing rules in `AGENTS.md` keep a check of a dependency
only for a known or suspected problem. Only the recursor links are such a
problem for our pages.

## Decision

### 1. A separate core documentation build

A new Nix derivation, `apiReferenceCore`, runs `bibPrepass`, `genCore Init`
and `genCore Std` in an empty directory, and stores the resulting build
directory with `api-docs.db`. Its inputs are the Lean toolchain and the pinned
doc-gen4 only. Its commands are in the Nix file, not in a repository script, so
a change to the repository's tools does not rebuild it. Nix and the CI cache
reuse it until the toolchain or doc-gen4 changes.

`apiReferenceBase` copies that build directory, runs `single` for each public
module and `fromDb`, and then applies the correction of decision 2.
`tools/ci_store_gc.py` keeps `apiReferenceCore` in the saved cache.

### 2. No checks of doc-gen4's output, except one known bug

- **`validate_reference` is removed.** The build no longer checks module
  pages, source-link prefixes, local links or anchors in the generated pages.
- **The correction of Lean's `Init/Tactic.html` typo is removed.** The typo is
  in Lean's documentation, not in ours.
- **The recursor-link correction stays, for our pages only.** It is the one
  known doc-gen4 problem on our pages. It names an upstream report to doc-gen4.
  When it finds no recursor link to correct on our pages, the build fails with
  a message that the doc-gen4 bug may be fixed and that the correction can be
  removed.

### 3. No second documentation inventory

The reference build no longer runs `tools/public_doc_inventory.py`. The
inventory is a gate on our sources: every public declaration and field has a
checked Verso docstring. `just documentation-inventory` already runs it in
`just test` and `just test-full`. In the reference build it only repeated the
gate and copied its report into the reference. The reference no longer
contains `public-doc-inventory.json`.

### Tests of our code

The reference build contains this code of ours. Each part has a test that
checks our code, not doc-gen4:

| Our code                                                                                          | Its test                                                                                                                                                                                                                             |
|---------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| The commit in the source links (`tools/api_reference_links.py`)                                   | The checks of the link step, and `tests/test_api_reference.py`                                                                                                                                                                       |
| The recursor-link correction                                                                      | Unit tests with HTML fixtures                                                                                                                                                                                                        |
| The arguments that we give to doc-gen4: the modules, their source URIs, the order of the commands | **New:** a unit test that runs the generator on a fixture source tree with a stand-in for doc-gen4, which records its arguments. Each public module is given once, with the URI of its own file, and `single` comes before `fromDb`. |
| The documentation inventory tool                                                                  | `tests/test_public_doc_inventory.py`                                                                                                                                                                                                 |

A failing doc-gen4 call fails the build. That prevents a partial reference, but
it is not a test of our code.

The completeness of our documentation is not a test of the reference build. It
is the content gate `just documentation-inventory`, with the Lean compiler,
which checks the names, terms and assertions in our Verso docstrings.

## Evidence

Each question was answered on macOS arm64 on 2026-10-09:

| Question                                                          | Answer                                                                                                                                                              |
|-------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Does a build from a copied core database give the same reference? | Yes. All 1,186 files match the build in one database, byte for byte.                                                                                                |
| Does the core database contain paths of its build?                | No. No row contains the build directory, `/nix/store`, `/Users/` or `/private/tmp`.                                                                                 |
| Does `genCore` need our project?                                  | No. It ran in an empty directory, without `lake env`, in the same time.                                                                                             |
| How large is the core database?                                   | 95 MB, 13.2 MB with zstd level 3.                                                                                                                                   |
| Should the core build also store its pages?                       | No. `fromDb` writes all 1,170 pages in 8.6 s.                                                                                                                       |
| Do our pages need the recursor-link correction?                   | Yes. Of the 178 corrections, 3 files are ours and 46 are Lean's.                                                                                                    |
| What does the correction of our pages cost?                       | The correction must read our 24 pages and the 27 Lean pages they link to, for their anchors. Parsing them took 1.0 s, against 158 s for both passes over all pages. |

## Expected effect

A pull request that changes a Lean source runs the Lean build, `single`,
`fromDb` and the correction of our pages: about 7 + 17 + 9 + 1 s, about 34 s
instead of about 346 s. A pull request that does not change Lean
sources still reuses the whole base build, as after PR #63. A Lean toolchain
or doc-gen4 upgrade rebuilds the core documentation once, about 150 s.

The saved cache grows by about 13 MB compressed for each platform.

## Consequences

- The published reference keeps all 1,170 pages. A broken link that doc-gen4
  or Lean writes is no longer reported by the build. The reference is not
  hosted yet.
- The `reference-check.json` report records the recursor corrections on our
  pages and the source links of the link step.
- The reference artifact no longer contains `public-doc-inventory.json`. The
  inventory report stays a result of `just documentation-inventory`.
- [API reference](api-reference.md) and [CI](ci.md) describe the build without
  the checks and without the inventory.
- The requirements of the checked API reference task (issue #26) become
  narrower: the owner decides this with this ADR.

## Alternatives considered

**Leave the build as it is after PR #63.** Rejected. Pull requests that change
Lean sources are the main development work, and each one would keep paying
for the core documentation and the checks of Lean's pages.

**Check our pages on each build.** Rejected. The checks of our pages also test
doc-gen4. No problem is suspected besides the recursor links, which the
correction handles.

**Check doc-gen4's output at each doc-gen4 or Lean upgrade.** Rejected. An
upgrade alone gives no reason to suspect a problem, and we do not run a
dependency's tests at its upgrades.

**Build the reference only on `main`.** Rejected by the owner on 2026-10-08,
when option A of PR #63 kept the reference check on pull requests.
