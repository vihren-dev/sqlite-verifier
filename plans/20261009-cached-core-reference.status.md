# Status: cached core API reference without checks of doc-gen4

Created 2026-10-09. Status: IN PROGRESS.
Task: [task](20261009-cached-core-reference.task.md).
ADR: [ADR 0009](../docs/adr-0009-cached-core-reference.md).

Relevant files: `build-support/api-reference-core.nix`,
`build-support/api-reference.nix`, `build-support/default.nix`,
`tools/api_reference.py`, `tools/api_reference_links.py`,
`tests/test_api_reference.py`, `tools/ci_store_gc.py`,
`tests/test_ci_store_gc.py`, `docs/api-reference.md`, `docs/ci.md`,
`build-support/README.md`.

## Progress

- 2026-10-09: ADR 0009 accepted and merged in PR #65. Task and status files
  created. PR #65, a documentation-only change, took 8 s and 11 s on Linux CI,
  against 8.5 minutes for PR #61 before PR #63.
- 2026-10-09: implemented. `build-support/api-reference-core.nix` builds the
  core database; `apiReferenceBase` copies it, runs `single` and `fromDb`, and
  corrects recursor links on our pages. `validate_reference`, the
  `Init/Tactic.html` correction and the inventory run in the reference build
  are removed. `tools/ci_store_gc.py` roots `apiReferenceCore`. Local Nix
  measurements on macOS arm64, with the sandbox:

  | Build | Built | Time |
  | --- | --- | --- |
  | First build, nothing cached | core, base, link step | 194 s |
  | After a Lean source change, core cached | base, link step | 41.9 s (base build phase 37 s) |

  The Lean change was one comment line in `SqliteVerifier/Model.lean`, reverted
  after the build. Before this change, the base build phase took about 346 s
  locally and 379 s on CI. The base build used the same Lean sources as the
  earlier base build `s1gxr555`; all 24 pages of our modules are byte-identical.
  The other differences are 46 Lean library pages without the old corrections,
  the report, and the removed `public-doc-inventory.json`. The correction
  changed 10 links on our pages.

## Remaining

- The upstream report of the recursor-link bug to doc-gen4. Filing it needs the
  owner's approval.
- Hosted CI of the pull request, and the reference step after the merge.
