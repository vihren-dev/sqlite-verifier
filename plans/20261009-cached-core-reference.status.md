# Status: cached core API reference without checks of doc-gen4

Created 2026-10-09. Status: DONE on 2026-10-09.
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

- 2026-10-09: commit `b4cd7536`. 149 tests pass, including the Nix source
  identity, Nix test target and test ownership tests.

- 2026-10-09: PR #67 merged. Its Linux CI spent 285 s in the reference step,
  with no cached core build, against 402 s in PR #63.
- 2026-10-09: with the owner's approval, filed
  [doc-gen4 issue 423](https://github.com/leanprover/doc-gen4/issues/423), with
  a five-line reproduction. The cause is in doc-gen4's code, unchanged on its
  `main` at `fd5ce8f`: `buildName2ModIdx` maps an internal name such as
  `Eq.ndrec` only to its target module, and `declNameToLink` uses the internal
  name as the anchor. doc-gen4 PR #347 introduced this, not PR #371. All 10
  corrected links on our pages are `▸` links to `Eq.ndrec` in derived `decEq`
  equations. The workaround docstring, `docs/api-reference.md` and ADR 0009 name
  the issue, which resolves review finding `20261009T075621Z-b4cd7536#1`.

- 2026-10-09: the `main` run for PR #67 (`37904138843`) passed on both
  platforms, and both Attic publish jobs passed. A re-run of PR #68's CI
  (`37905384166`, attempt 2) then restored the core build: its log lists three
  derivations to build, the link tools, the base and the link step. PR #68
  changes `tools/api_reference.py`, an input of the base, so the base was
  rebuilt as after a Lean source change. Linux step times:

  | Step | PR #68 re-run | PR #67 | PR #63 |
  | --- | --- | --- | --- |
  | Build checked API reference | 55 s | 285 s | 402 s |
  | Run checks in one pinned environment | 56 s | 439 s | 389 s |
  | Restore Nix builds and test results | 99 s | 126 s | 71 s |

  The whole Linux job took about 5.5 minutes, against 14 minutes 47 seconds for
  PR #67. The task is DONE.
