# Continuous integration

`.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual
requests. Both jobs enter the committed Nix environment and run `just setup`,
`just check`, and `just package`. Adding checks to the shared recipes extends CI.
Jobs have a 30-minute timeout; individual tests keep their own shorter limits.

The matrix follows GitHub's documented native runner architectures:
`ubuntu-22.04` is x64 (`x86_64-linux`), and `macos-14` is Apple Silicon
(`aarch64-darwin`). Each job also checks Nix's actual host system before building.
See [GitHub's hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Runner image updates remain controlled by GitHub; project dependencies are pinned
separately in `flake.lock` and `lean-toolchain`.

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

Successful jobs retain clearly labeled **development-source** archives for 14
days. They are source snapshots, not installable verifier artifacts or verification
results. Installable runtime packaging, representative packaged CLI smoke tests,
and the tag-triggered GitHub Release workflow remain pending the checked CLI.
A passing foundation workflow does not mean roadmap Step 1 is complete.
