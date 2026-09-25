# Continuous integration

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

Each build job enters `nix develop path:./nix#capture` once for setup, the Linux
sandbox check and its selected recipe. This explicit path contains only the
environment definition, even in additional Jujutsu workspaces. Adding checks to
shared recipes extends CI. Superseded ordinary runs on the same ref are cancelled;
tags and manual runs have unique concurrency groups and are never auto-cancelled.
Jobs have a 30-minute timeout; individual tests keep their own shorter limits.

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

## Maintainer prerelease

From the primary checkout, after reviewed `main` CI is green and release notes
are current, create a fresh engineering prerelease tag and transport it:

```sh
jj tag set v0.1.0-rc.1 -r main
git push origin refs/tags/v0.1.0-rc.1
```

The installed Jujutsu supports tag creation, but its push command transports
bookmarks; Git is used for this tag-only push. The tag workflow reruns both
platform checks and marks hyphenated version tags as prereleases. Watch that run
and verify both published archives and checksum files before announcing it.
Never move or reuse a released or failed release tag; use the next RC tag after
a fix. A stable release remains pending real-pilot/product-owner acceptance.
No release tag has been created by the packaging implementation itself.
