# Nested pytest timeout cleanup

Created: 2026-09-28. Status: DONE (bounded Darwin implementation and review).

Bounded follow-up to [the accepted pytest/Nix task](20260928-pytest-nix-builds.task.md)
and [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md), based on `d7ca0c2b`.
Author: formal_preservation. Independent reviewer: adr1_inventory; root integrates.

The final requirement audit found that each nested `run_command` starts a new
session. Killing the outer pytest group therefore left inner verifier/Lean
groups alive. The nesting includes benchmark, CI, suite and command runners;
the production sandbox also deliberately starts a separate session.

`tests/runtime_support.py` now freezes the owned original group, discovers
descendants by native POSIX parent/group IDs, and repeats discovery until all
observed descendants are stopped or terminal. It kills only those owned groups
and PIDs, reaps the direct child, and checks descendant termination within a
five-second cleanup deadline. Zombies count as terminated: macOS cannot waitpid
unrelated descendants. Pipe draining has a separate two-second bound. Discovery
errors survive in command JSON as `cleanup_error`; every recorded stopped process
is signaled even when another signal fails. No production policy, environment
allowlist, timeout or proof behavior changes.

This is cleanup of connected descendants and the original group, not a new
containment boundary. A session already daemonized and reparented before the
timeout has no attributable POSIX ancestry; production sandbox containment
remains responsible for untrusted code. If the OS cannot terminate the direct
leader even after SIGKILL and the final bounded wait, that wait exception escapes
rather than inventing an exit status. Normal timeout and discovery failures retain
the complete command observation and artifacts.

`tests/test_timeout_cleanup.py` contains four independently selectable native
regressions: nested helpers plus a further detached child and surviving unrelated
sibling; exited group leader with held pipes; failed discovery with bounded pipe
draining; and the actual production sandbox launcher. All are source integration
cases requiring `/bin/ps`; the sandbox case also requires the host sandbox.

Validation used one pinned shell after `python3 tools/check_resources.py` passed:

- `python3 -m pytest tests/test_timeout_cleanup.py -q --suite nested-timeouts`:
  four passed in 14.48s on native Darwin.
- `python3 -m pytest tests/test_timeout_cleanup.py tests/test_pytest_harness.py
  tests/test_independent_suites.py tests/test_runtime_selection.py
  tests/test_sandbox.py -q --suite timeout-regressions`: 33 passed and two subtests
  passed in 25.56s.
- Negative control replacing `terminate_tree` with the previous `killpg(SIGKILL)`
  behavior: the nested-session regression failed in 3.12s because the inner
  `middle.pid` remained live (`Ss`, parent 1). Regression cleanup removed the
  recorded children. This is expected failing evidence, not an acceptance run.

Reviewer requested observed stopped-state convergence because signal delivery is
asynchronous; that correction is implemented and independently approved. Final
focused rerun with `--suite timeout-regressions-final`: 33 passed and two subtests
passed in 25.72s. All four new cases passed as separate pytest invocations (3.58s,
3.40s, 5.29s, 3.38s including process startup), then in reversed order (14.67s).
The existing harness descendant case and report-timeout parameter also declare
their `/bin/ps` resource. Selected strict catalogue output is
`build/timeout-catalogue.json`; inventory additions and merged hashes are owned by
adr1_inventory to avoid concurrent edits. Native Linux execution remains a CI
acceptance responsibility; no Linux result is claimed by this local record.
