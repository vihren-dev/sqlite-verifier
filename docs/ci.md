# Continuous integration

CI uses Nix to cache builds and expensive hermetic pytest suites. The earlier
[ADR 0001](adr-0001-pytest-and-nix-ci.md) unit-result receipts and coverage
aggregation have been superseded by [Nix test targets](../build-support/README.md).

`.github/workflows/ci.yml` checks Linux and macOS on pull requests, main pushes,
release tags and manual requests. `tests/ci_scope.py` routes documentation-only
changes to link checks, ordinary changes to `just test`, and runtime/package
changes to `just package`. Tags and manual requests always package.

Each native job enters the pinned Nix environment once. `tools/ci_checks.py`
checks resources, builds the runtime and
invokes the selected recipe. `just test` builds four independent Nix test targets
with `nix-build -A tests`; the flake exposes the same derivations as
`checks.<system>`:

- `tests.kernel`: real Lean compilation and proof-checker replay attacks.
- `tests.model`: production SQL translation, pinned native SQLite observations
  and concrete Lean model assertions.
- `tests.atuin`: the Atuin application CLI scenarios.
- `tests.cli`: public-entrypoint acceptance and adversarial input scenarios.

Each target runs ordinary pytest on a cache miss. Its explicit source files,
Python/pytest, native tools, Lean artifacts and command determine its Nix identity.
Successful outputs retain pytest's JUnit XML. There is no Python cache validator or
coverage-report gate. Nix sandboxing is enabled, with fallback disabled.

The remaining cheap source cases run in one pytest invocation. Cases marked
`requires_nix` (source identities, test-target invalidation, environment snapshots,
installer cache paths) run in `just test-nix`, which `just package` includes; CI
routes changes to Nix, build, tooling, packaging and those test files to packaging. `just test-atuin` selects
only the cached Atuin target. Tests use trusted repository fixtures; no production
sandbox is supplied or tested. Nix daemon and installation tests run on the host.
Cheap unit tests rerun normally. Direct `just test-cases FILE` always executes
pytest, even if the corresponding Nix target is already cached.

The pinned cache-nix-action restores the Nix store using a platform/environment
prefix and a commit-specific key. Only successful main jobs save caches. PRs and
tags restore them. Nix, not the GitHub cache key, determines which outputs can be
reused. An unrelated test edit can reuse kernel/model results; changing a declared
input creates a different test derivation. No extra signing credentials, custom
source fingerprinting in production CI, or checkout build caches are required.

Host JUnit reports, cached Nix test outputs and CI phase diagnostics are
retained for 14 days. Pytest's exit status decides success. Individual subprocess
and whole-command deadlines remain bounded (a timed-out test command's process
group is killed); the job limit is 30 minutes.
Superseded ordinary runs are cancelled; release/manual runs are not.

The matrix follows GitHub's documented native runner architectures:
`ubuntu-22.04` is x64 (`x86_64-linux`), and `macos-14` is Apple Silicon
(`aarch64-darwin`). Each job also checks Nix's actual host system before building.
See [GitHub's hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Runner image updates remain controlled by GitHub; project dependencies are pinned
separately in `nix/flake.lock` and `lean-toolchain`.

Action commits were resolved from official repository tag references on
2026-09-24: `actions/checkout` v6, `cachix/install-nix-action` v31 (an annotated
tag, dereferenced to its commit), and `actions/upload-artifact` v4. The workflow
pins the full commits rather than floating tags. Checkout does not persist
credentials, and the workflow requests read-only repository content permission.

Successful packaging jobs retain development-source snapshots and checked native
runtime archives for 14 days; ordinary checks do not create these archives.
Runtime
acceptance installs into a fresh directory with spaces, Unicode and URI-special
characters, and checks both parsers, the positive, refuted and unsupported examples,
the installed dependency roots, and the Atuin cases under
a controlled environment without elan or ambient Python imports. The Nix local
cache retains the complete content-addressed runtime closure with import
verification enabled. Execution isolation is the caller’s responsibility.

Pushes of `v*` tags run the same two-platform checks. Only after both pass does the
release job download their artifacts, verify the archive checksums, and create a
GitHub Release. The publishing job alone has write permission. No existing release
is overwritten. The download-artifact v5 commit was resolved from the official
repository tag on 2026-09-24. Tag creation remains a coordinated release action.
A passing engineering workflow does not mean roadmap Step 1 is complete.

The separate target-owned `Protected approved baseline` workflow is unchanged.
Documentation routing does not authorize changed approved sources or manifests.

## Maintainer release

From the primary checkout, after reviewed `main` CI is green and release notes
are current, create a fresh release tag and transport it (use a hyphenated version for a prerelease):

```sh
jj tag set v0.1.2 -r main
git push origin refs/tags/v0.1.2
```

The installed Jujutsu supports tag creation, but its push command transports
bookmarks; Git is used for this tag-only push. The tag workflow reruns both
platform checks and marks hyphenated version tags as prereleases. Watch that run
and verify both published archives and checksum files before announcing it.
Never move or reuse a released or failed release tag; use a fresh version after
a fix. The owner accepted the Step 1 product on 2026-09-25. Stable v0.1.1 was
published on 2026-09-28 after both complete platform jobs passed twice at `7a99c71f`;
published checksum files match the archive asset digests. The failed v0.1.0 tag
remains unchanged, and v0.1.0-rc.1 is an earlier engineering preview.

The [native benchmark protocol](adr1-benchmarks.md) records the earlier isolated
60-job comparison. Its workflows and tools were removed on 2026-09-29.
