# Cached core API reference without checks of doc-gen4

Created 2026-10-09. Status: IN PROGRESS.
Decision: [ADR 0009](../docs/adr-0009-cached-core-reference.md), accepted by
the owner on 2026-10-09.

## Outcome

1. A Nix derivation `apiReferenceCore` builds the doc-gen4 core documentation
   (`bibPrepass`, `genCore Init`, `genCore Std`) from the Lean toolchain and
   the pinned doc-gen4 only, with its commands in the Nix file.
2. `apiReferenceBase` starts from a copy of the core build, runs `single` for
   each public module and `fromDb`, and corrects recursor links on our pages.
   It runs no documentation inventory and no `validate_reference`.
3. The recursor-link correction covers our pages only. It fails the build
   when it finds nothing to correct on our pages. The `Init/Tactic.html`
   correction is removed.
4. `tools/ci_store_gc.py` keeps `apiReferenceCore` in the saved CI cache.
5. A pull request that changes a Lean source, with the core build cached,
   spends about 34 s on the base build instead of about 346 s.

The `apiReference` link step and `just reference HASH` keep their interface.
The pages of our modules are the same as before.

## Tests

- `tests/test_api_reference.py`: a unit test runs the generator on a fixture
  source tree with a stand-in for doc-gen4 that records its arguments. Each
  public module is given once, with the URI of its own file, and `single`
  comes before `fromDb`. Unit tests with HTML fixtures show that the
  correction changes only our pages, keeps existing raw fragments, and fails
  when our pages need no correction.
- A test that `build-support/api-reference-core.nix` takes only the toolchain
  and doc-gen4, and that `tools/ci_store_gc.py` roots `apiReferenceCore`.
- A local Nix check: after the core build, a change to one Lean source
  rebuilds `apiReferenceBase` without `apiReferenceCore`. Its time is recorded.
  The pages of our modules equal those of the previous build.
- Hosted CI: the pull request's own run, and later runs after the merge, with
  the time of the reference step recorded.

## Relevant source and constraints

- `tools/api_reference.py` drives doc-gen4; it is close to the 200-line limit.
  `validate_reference` and the core correction go away; the module list,
  the source URI and the commands stay.
- doc-gen4 runs `single` and `fromDb` through `lake env` in our project root;
  the core commands need no project (ADR 0009 evidence).
- `bibPrepass` creates the `doc` and `doc-data` directories next to
  `api-docs.db`; the base build copies the whole core build directory.
- The correction needs the anchors of the pages that our links point to,
  including some Lean library pages; it reads only those.
- `docs/api-reference.md`, `docs/ci.md` and `build-support/README.md`
  describe the checks and the inventory report, and change with the code.
- The recursor bug needs an upstream report to doc-gen4. Filing it is an
  outward action that the owner approves.
