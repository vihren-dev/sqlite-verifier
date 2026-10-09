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

Codex review of `8e5f0b27`: no "must" findings, two "should" findings, both
fixed in `19ac767c` (a test now pins the upload step's restore condition,
client, login and push; the docs say only the check job substitutes from
Attic). Replacing the upload with `true` now fails a test. Review of
`19ac767c`: no findings. Not verified locally: hosted cache restoration and
the upload itself.

2026-10-09: the first `main` run with publishing (37787820192) passed both
checks, but both publish jobs reached their 60-minute limit and the run was
cancelled. atticd logged `Connection pool timed out` (SQLite allows one
writer; two runners uploaded at once). The devops repository moved Attic to
PostgreSQL (devops pull requests 19 and 20), which recreated the cache with a
new signing key, `sqlite-verifier:XgeRqTIGBEw3VP8GPrzSvdU+5t1lJz7uEMhIG1lh7QE=`.
The workflow, its test constant and `docs/ci.md` now trust that key.
