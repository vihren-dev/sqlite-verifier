# Substitute from and publish to the Vihren Attic cache: status

Created 2026-10-08. Status: IN PROGRESS.
Task: [20261008-attic-store-publish.task.md](20261008-attic-store-publish.task.md).
Related: [20260929-attic-ci](20260929-attic-ci.status.md) (rolled back),
devops `plans/20261008-attic-ci-cache.*`.

Started from `main` at `e39eea04` in a separate workspace (`attic-ci`) so other
agents' workspaces are untouched. No open pull request changes `.github/`.
The `attic-publish` environment (main only) and its `ATTIC_WRITE_TOKEN` exist
since 2026-09-29; devops pull request 17 removes its administrator bypass.
