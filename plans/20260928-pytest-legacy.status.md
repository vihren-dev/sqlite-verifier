# Legacy parser test entrypoint closeout

Created: 2026-09-28. Status: DONE (bounded cleanup).

Part of [the accepted pytest/Nix task](20260928-pytest-nix-builds.task.md).
Author: formal_preservation; reviewer/integrator: root.

Removed the unused `parser_build_test.py --native-reuse` main loop and ordinary
`unittest.main` branch. Caller search across recipes, workflows, tools, docs and
tests found no remaining executable caller; historical baseline/inventory labels
remain intentionally unchanged. The five unittest methods and two parametrized
pytest native-reuse cases are unchanged and remain authoritative.

After the resource guard, one pinned Nix shell ran `python3 -m pytest
tests/parser_build_test.py tests/test_parser_cache_environment.py -m unit
--runtime-root /nix/store/00b6q3j0lwsh55597prmyv63awq5bsff-sqlite-verifier-runtime-1
-q --suite parser-entrypoint-cleanup`: seven passed, nineteen subtests passed,
two deselected, in 0.18s. Strict catalogue collection retains all seven parser
nodes, including both native profiles. This workspace has no checkout parser
stamps, so no new native build was performed; integrated host checks exercise
the unchanged native-reuse cases against the root workspace's existing stamps.
