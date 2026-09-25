# Native runtime packaging status

Created: 2026-09-24. Status: DONE — published engineering prerelease on 2026-09-25.
Task: [runtime packaging](20260924-runtime-packaging.task.md).
Source: Step 1 task, engineering brief v0.5, roadmap proposal v0.1.
Owner: technical_lead; independent reviewers: root and conformance_review.

## Checked implementation

The coordinator accepted Nix as the installer prerequisite. Native archives carry
CLI/parser/checker/library, standard Lean object/private/IR/shared-library files,
Lean LICENSE/LICENSES, examples and docs. A local Nix binary cache preserves
upstream signatures for Python, Linux bubblewrap and exact loader dependencies.
The builder verifies the cache signatures. Installation is offline, retains GC
roots, refuses an existing destination, and launches isolated Python with bundled
Lean. It does not use ambient Python imports, elan or caller-selected Lean.

The shared recipes build/check once, refresh bounded coverage, build a runtime,
install-smoke its actual CLI, then retain a source snapshot. CI retains coverage
JSON, including available failed reports, and native archives with checksums.
Both platform jobs must pass before a v-tag workflow can publish. Hyphenated
version tags are explicitly prereleases. Already compressed runtime uploads use
compression level zero. The maintainer tag procedure is in docs/ci.md.

## Evidence

The corrected macOS archive SHA-256 is
`8637aa7b94853511cee995b082280e7333d370d0c70a2b374663c470724170aa`
(972 MiB compressed). Author and independent conformance reviewer both installed
that exact archive into temporary paths containing spaces and ran the real CLI
positive, checked-refutation and unsupported cases with poisoned ambient Python
and Lean variables. All passed. No public tag or release was created by this unit.

Shared macOS checks passed: model proofs, parser, upstream/native and derived
native/model cases, kernel gate, compiler isolation and complete CLI examples.
The three exact-loader regressions and two installer regressions pass. Workflow
actionlint and installer/workflow ShellCheck pass. The integrated coverage command
returns EVIDENCE_CHECKS_PASSED. Source manifest generation and a real source CLI
positive proof also pass. The final shared recipe graph was checked by dry-run.

Independent review found a destination-ownership cleanup race; exclusive creation
outside cleanup now preserves another installer's directory. A real extracted
smoke found literal spaces invalid in Nix cache URIs; byte-wise URI encoding fixed
it, with actual installer tests for spaces, Unicode, percent and fragment markers.
Nix realization disables substitution and build fallback. Exact validated native
store roots replace whole-store sandbox access.

## Integration and outstanding evidence

Exact roots were split into checked commit `101809c4` to unblock source Linux CI.
Nix elan patches Linux's ELF interpreter to a store path, so `just build` emits
project-owned loader metadata and the compiler/checker consume it. The packaging
unit was based on integrated `bc1b02c8`. Hosted Linux exposed LLVM linker scripts
and compiler SDK libraries being scanned as runtime objects. Reviewed fixes
`cf2dde6d` and `522b2b57` now share the runtime copy/inspection selection: direct
system libraries and the complete `lib/lean` import tree. Actual absolute bundled
dependencies must belong to that copied set; unresolved or excluded SDK
dependencies remain errors. Root, technical lead and conformance review accepted
the changes. The three focused regressions and actual macOS collector pass.

A fresh macOS archive build and installed smoke against exact `522b2b57` passed
after the new copy selection. `just build && just runtime-package` completed with
exit zero, including native binaries, loader manifest, offline cache signatures,
extraction/installation and isolated VERIFIED, VIOLATED and UNSUPPORTED cases.
The rebuilt archive SHA-256 is
`3f89e1c416a1781423c9565de78ba508189409c8a53ec4b7d63be572b89c562e`
(972 MiB). Author and independent conformance reviewer both accepted this exact
archive after installed smoke tests; the earlier checksum describes its predecessor.

Hosted Linux diagnostics identified a missing lexical Nix package root when a
library symlink resolves into another package. Reviewed fix `5ab817ec` retains
both exact roots. No loader-cache permission or whole-store access was added.
Run [35998140680](https://github.com/vihren-dev/sqlite-verifier/actions/runs/35998140680)
at integrated `c840b0434186` passes both platform jobs, including complete source
checks, coverage, native packaging and actual offline installed smoke tests.

Tag `v0.1.0-rc.1` names that checked commit. Its independent release workflow
[36102477873](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36102477873)
passes both platform checks and the publication job. The
[public prerelease](https://github.com/vihren-dev/sqlite-verifier/releases/tag/v0.1.0-rc.1)
contains exactly two native archives and their checksum files; it is not a draft.
The publishing job rehashed both archives before publication. The integration
engineer downloaded the two checksum files and matched their names/hashes against
GitHub's archive SHA-256 digests, also verifying the exact tag commit.

| Platform | Archive bytes | SHA-256 |
| --- | ---: | --- |
| aarch64-darwin | 1,019,234,481 | `8a4b9000558936dc9b352ca3eb0f2e65c5f0c88d28f5e5a96d905a7f1f2d7346` |
| x86_64-linux | 1,002,219,755 | `cfae408d23d539bfebe723f872f685e9baa9ceba3b2a6922152784ddcec4af27` |

Packaging and coordinated publication are DONE. No bit-for-bit reproducible archive
claim is made: tar/gzip metadata and native build timestamps are not normalized.
Real-pilot acceptance and product-owner review remain separate Step 1 requirements.
