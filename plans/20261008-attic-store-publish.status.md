# Substitute from and publish to the Vihren Attic cache: status

Created 2026-10-08. Status: IN PROGRESS.
Task: [20261008-attic-store-publish.task.md](20261008-attic-store-publish.task.md).
Related: [20260929-attic-ci](20260929-attic-ci.status.md) (rolled back),
devops `plans/20261008-attic-ci-cache.*`.

Started from `main` at `e39eea04` in a separate workspace (`attic-ci`) so other
agents' workspaces are untouched. No open pull request changes `.github/`.
The `attic-publish` environment (main only) and its `ATTIC_WRITE_TOKEN` exist
since 2026-09-29; devops pull request 17 removes its administrator bypass.

The check job adds the Attic cache as an extra substituter with its signing
key, `connect-timeout = 5` and `fallback = true`; `sandbox-fallback` stays
disabled. A new `publish-nix-store` job (after `release`, so the check-job
step tests keep their scope) needs `check`, runs only for `main` pushes and the
nightly schedule, uses `attic-publish`, has `continue-on-error` and a 60-minute
limit, restores the check job's exact cache key without saving, and pushes
`nix path-info --all` (without `.drv` files) with the pinned Attic client.
The pinned cache action provides `save` and `hit-primary-key`.

Four workflow tests added. actionlint 1.7.12 (with ShellCheck) passes;
`tests/test_ci_workflow.py` and `tests/test_ci_scope.py`: 10 passed, 35
subtests. Removing `environment: attic-publish`, or giving the check job the
token, each fails a new test. `docs/ci.md` describes the substituter, the
publishing job and the token boundary; `tests/docs_test.py` passes.
