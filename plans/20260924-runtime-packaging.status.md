# Native runtime packaging status

Created: 2026-09-24. Status: IN PROGRESS — not DONE.
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
unit is based on integrated `bc1b02c8`. Latest hosted Linux then exposed a separate
collector issue: LLVM's libc++.so is a linker script. The integration engineer
owns the ELF-library filter and regression in a separate checked change.

Hosted Linux package execution and coordinated engineering prerelease publication
remain pending; this task remains IN PROGRESS. No bit-for-bit reproducible archive
claim is made: tar/gzip metadata and native build timestamps are not normalized.
Real-pilot acceptance and product-owner review remain separate Step 1 requirements.
