# Source-mode loader test import isolation

Created: 2026-09-28. Status: DONE (scoped fix, Darwin reproduction and independent review).

Bounded follow-up to [the accepted pytest/Nix task](20260928-pytest-nix-builds.task.md)
and [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md), based on `cd81cf1d`.
Author: formal_preservation. Independent reviewer: adr1_inventory; root integrates.

Normal main source-mode CI run
[36410900455](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36410900455)
at `2bd6f604` exposed an import dependency in the loader unit case. Its dynamic
archive-builder import supplied `runtime_dependencies` but no packaging search
path for the newly added `relocate_elf` sibling. The complete unit collection had
masked this through other modules' import-time path setup. Source mode's separate
legacy partition, and selecting the case alone, expose the defect.

The fix scopes `sys.path` and the module cache to the dynamic import, removes any
previously loaded `relocate_elf` within that scope, and asserts that the real sibling
file was imported. Both global containers are restored on leaving the context.
All existing loader, store-root, copying and rejection assertions remain intact.
Production packaging, proof acceptance, caching and orchestration are unchanged.

Before the change, the exact case failed alone in the pinned environment in 0.04s
with the same `ModuleNotFoundError`. Both Linux and Darwin artifact audits found
all 416 source IDs once, with this single failed call and no other failed phase;
fresh coverage passed on both. Package installation correctly did not run after
the source failure. The normal fallback therefore remains unvalidated until the
corrected revision completes a new native CI run.

After `python3 tools/check_resources.py` passed, one pinned Nix shell supplied the
focused validation without a build:

- `python3 -m pytest
  tests/test_native_dependencies.py::NativeDependenciesTest::test_linux_loader_and_library_paths
  -q --suite source-loader-fixed`: passed in 0.10s.
- The 19 unit cases selected from `test_native_dependencies.py`,
  `test_runtime_package.py`, `test_runtime_staging.py`, `test_elf_relocation.py`
  and `test_resources.py` each passed as a separate process (3.83s combined), then
  passed reversed (0.17s pytest / 0.34s process time). Commands were bounded to
  30 seconds each; `build/loader-import-catalogue.json` records the exact IDs and
  `build/loader-import-order/` retains command observations and timing summary.
- A 15-second bounded adversarial invocation preloaded fake `runtime_dependencies`
  and `relocate_elf` modules, ran the same test, and checked the original `sys.path`
  list identity/content and both module objects were restored. It passed.

The complete caller search found no other dynamic `build_runtime` import. Its
ordinary test importers (`test_resources`, `test_runtime_package`,
`test_runtime_staging`) explicitly establish the packaging path; the CLI executes
the builder as a script, which supplies that path naturally. Reviewer adr1_inventory
approved the scope/exception restoration and verified all 13 preexisting assertion
expressions remain plus one sibling-origin assertion. No case IDs or markers
changed; the inventory's implementation hash and current source ranges need the
usual integration refresh. Native CI, cache pilot and rollout decisions remain
owned by the lead; this test-only change does not claim a new performance result.
