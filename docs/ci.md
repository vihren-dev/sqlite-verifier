# Continuous integration

[ADR 0001](adr-0001-pytest-and-nix-ci.md), accepted on 2026-09-28, authorizes
immutable project-build and pure-unit-result caching with compatible prefix
restoration, subject to its correctness and performance gates. Implementation is
[in progress](../plans/20260928-pytest-nix-builds.status.md). Production retains the
dependency-only fallback until native correctness and measured performance gates
pass. The workflow-dispatch `experimental-build-cache` input or a PR branch
prefixed `experiment/adr-0001-` exercises the new graph without enabling rollout.

`.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual
requests. The two required `Check` jobs remain present for every run. Their
scope is selected from the complete changed-path list by `tests/ci_scope.py`:

- Documentation-only changes check authored Markdown file links, without Nix or
  archives. External URLs and section anchors are outside this bounded check.
- Ordinary verifier, conformance and test changes run the full `just check` on
  both platforms. Unknown paths also run full checks.
- Packaging, CLI, parser, toolchain/environment, example and workflow changes run
  `just package`, including the complete checks and installed-runtime tests.
- Release tags and manual requests always run `just package`.

Each build job enters `nix develop path:./nix` once. `tools/ci_checks.py` runs
setup, the Linux sandbox check and its selected recipe. In experimental mode it
builds `runtime` and `unitChecks` with Nix, supplies their explicit roots to the
same fresh host recipe, and retains cached unit receipts separately. This explicit path contains only the
environment definition, even in additional Jujutsu workspaces. Adding checks to
shared recipes extends CI. Superseded ordinary runs on the same ref are cancelled;
tags and manual runs have unique concurrency groups and are never auto-cancelled.
Jobs have a 30-minute timeout; individual tests keep their own shorter limits.

After shared build and coverage prerequisites, kernel-gate and ordinary CLI suites
run with two workers on Linux. macOS runs them sequentially: hosted overlap caused
a valid proof to hit the unchanged production checker deadline. Each suite keeps
its own deadline (360 and 600 seconds), private
test directories and complete log under `build/test-logs/`. Both children are
awaited; either failure fails CI. Other suites remain sequential. Logs, fresh JSON/JUnit reports and failure artifacts are retained
on failure as well as success; cached unit reports use a separate directory. Runtime packaging reports copying, Nix export,
signature verification and compression times; installed Atuin output streams live.
The offline Nix cache uses its native zstd encoding; the outer archive remains
gzip level1. Nix verifies the decoded contents and signatures before archiving.

The pinned [cache-nix-action v7](https://github.com/nix-community/cache-nix-action/tree/7df957e333c1e5da7721f60227dbba6d06080569)
reuses the Nix store with an exact platform and `nix/flake.nix`/`nix/flake.lock`
hash key. Only successful `main` jobs save caches; pull requests and tags only
restore. The fallback has no prefix restoration and keeps checkout build outputs outside
the cache. Experimental mode uses the canonical `build-v2` environment/source
key and the matching environment prefix; Nix derivation identity decides reuse.
Only reviewed resource-free unit receipts may replace host unit execution.
Proof acceptance, conformance, host sandbox and installed tests always run freshly.
Neither mode adds checkout cache paths, purging, garbage collection or permissions.
A miss rebuilds from declared pinned inputs. Hosted cold
and warm package runs must establish whether restoration and saving pay for
themselves; the timing report records measured results rather than assuming a gain.
See [CI performance measurements](ci-performance.md) for complete runs and the
per-invocation import reuse that reduces checker work without caching verdicts.

The matrix follows GitHub's documented native runner architectures:
`ubuntu-22.04` is x64 (`x86_64-linux`), and `macos-14` is Apple Silicon
(`aarch64-darwin`). Each job also checks Nix's actual host system before building.
See [GitHub's hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Runner image updates remain controlled by GitHub; project dependencies are pinned
separately in `nix/flake.lock` and `lean-toolchain`.

The Linux job requires unprivileged bubblewrap user/network namespaces, rejects
workspace writes inside its test sandbox, and confirms temporary writes work.
It fails if those capabilities are unavailable. It does not change host kernel
settings, use a privileged container, or skip containment failures. This is a
runner capability check, not evidence that the production proof sandbox is
correct; its acceptance tests belong in `just check`. Bubblewrap describes the
policy responsibility in its [upstream documentation](https://github.com/containers/bubblewrap#sandbox-security).

Action commits were resolved from official repository tag references on
2026-09-24: `actions/checkout` v6, `cachix/install-nix-action` v31 (an annotated
tag, dereferenced to its commit), and `actions/upload-artifact` v4. The workflow
pins the full commits rather than floating tags. Checkout does not persist
credentials, and the workflow requests read-only repository content permission.

Successful packaging jobs retain development-source snapshots and checked native
runtime archives for 14 days; ordinary checks do not create these archives.
The fresh bounded `build/coverage.json` report is retained
for each platform, including failed reports when the file is available. The runtime package smoke installs into a fresh directory
with spaces and checks the real positive, refuted, and unsupported examples under
a controlled environment without elan or ambient Python imports. The Nix local
cache retains loader dependencies and does not disable signature checks.

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

The [native benchmark protocol](adr1-benchmarks.md) defines the isolated
60-job comparison and the evidence required before rollout.
