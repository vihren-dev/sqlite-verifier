# Substitute from and publish to the Vihren Attic cache

Created 2026-10-08. Status: DONE.

## Outcome

Every CI job that uses Nix substitutes from the publicly readable Attic cache
`https://cache.vihren.dev/sqlite-verifier` in addition to cache.nixos.org,
without credentials, so pull requests (including fork pull requests) reuse
outputs that `main` already built. A substitution failure falls back to a local
build; the cache can never fail or block a check.

After both native checks of a `main` push or a nightly run pass, a separate
job per platform uploads that run's Nix store to the cache. It restores the
store the check job saved, uploads only paths that cache.nixos.org does not
already provide, and runs with the `attic-publish` environment, which is the
only holder of `ATTIC_WRITE_TOKEN` and deploys only from `main`. No other job
receives the token. A failed or slow upload does not fail the workflow, does
not delay the required checks, and changes no check result.

The GitHub Actions cache keeps its current role unchanged. The earlier attempt
(`20260929-attic-ci`) uploaded inside the check job and hit its step deadline at
about 1.8 MiB/s; the host's server has since been measured at about 50 MiB/s
after a restart (devops `plans/20261008-attic-ci-cache.status.md`).

## Tests

`tests/test_ci_workflow.py` asserts: the check job's Nix configuration adds the
cache as an extra substituter with its signing key, enables substitution
fallback and keeps sandbox fallback disabled; the check job never references
`ATTIC_WRITE_TOKEN`; the publishing job needs the check job, runs only for
`main` pushes and the nightly schedule, uses the `attic-publish` environment,
cannot fail the workflow, has its own deadline and restores without saving.
actionlint and the existing workflow, routing and documentation tests pass.
Hosted evidence: a pull request run substitutes from the cache, and the first
`main` run after merge uploads within the publishing job's deadline.

## Tricky points

- `check_job_steps()` treats the text between `check:` and `release:` as the
  check job; the publishing job goes after `release`.
- Same-repository pull requests receive repository secrets; only the
  environment's branch policy keeps the write token from them.
- `fallback` (use a local build when a substitute fails) is not
  `sandbox-fallback`, which stays disabled.
- The publishing job restores the exact key the check job saved; a cache
  miss uploads nothing and is not an error.
- The cache must be public before merging, or pull request substitutions see
  401 responses (harmless with fallback, but noisy).
