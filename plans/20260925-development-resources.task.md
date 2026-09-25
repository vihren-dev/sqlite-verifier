# Bound development storage and verification cost

Created: 2026-09-25. Status: IN PROGRESS.

## Required outcome

The owner's development-process report identifies repeated Nix snapshots of
generated artifacts in non-Git Jujutsu workspaces. Entering the pinned environment
must use only a small, explicit environment directory. Changes to source, dist/,
build/, .lake/ or workspace metadata must not affect that environment's source
identity or copy those trees into the Nix store. Keep the current toolchain pins.
Every active local, direnv and CI entry point must use this boundary. Developers
can run a batch in the appropriate shell without a nested environment invocation.

The integration engineer owns build resources and release correctness. Before
expensive toolchain/package work, a bounded check rejects less than 10 GiB free
with an actionable diagnostic; unexpectedly large environment inputs also reject.
Artifact output remains outside environment inputs. Cache retention and cleanup
authority are explicit and never include user databases or volumes. Any remaining
targeted deletion requires the owner's separate scoped approval.

Routine work runs focused tests; integration runs complete checks on both native
platforms. Packaging/runtime changes and release candidates retain complete
archive and installed-runtime checks. Documentation-only CI runs documentation
checks. Superseded ordinary CI is cancelled; release runs remain protected.
Required branch-check names and the target-owned baseline gate remain effective.

The aggregate verification command executes each evidence-producing comparison
once and reports evidence from that same invocation, with complete case sets and
failure/freshness validation. Standalone coverage remains reproducible. Parser
compilation is incremental with correct source/tool dependency invalidation;
upstream hash validation and both independent pinned versions remain mandatory.

## Acceptance evidence and boundaries

- A real Nix regression observes the environment source path/size before and
  after changes to generated/workspace directories, including a non-Git workspace.
- Low-space and oversized-input checks fail clearly; sufficient resources pass.
- CI routing checks cover documentation, verifier, packaging/runtime and release
  changes, including ordinary cancellation versus release preservation.
- Aggregate evidence tests reject missing, stale, duplicate and failed results;
  a bounded integrated invocation demonstrates no duplicated comparisons.
- Parser checks cover no-op rebuild, changed source/tool inputs, missing outputs
  and pinned-source tampering, followed by both parser regression suites.
- Independent technical review and relevant existing checks pass before checked
  units are committed. Preserve all unfinished Atuin work and protected baselines.

Relevant code: flake.nix/flake.lock, .envrc, justfile, parser/build.py,
conformance/coverage_report.py, packaging/build_runtime.py, CI workflows and
onboarding/team documentation. A derivation filter or .gitignore alone cannot
fix a flake source that has already included the changing workspace.

Owner: integration engineer. Challenger and integration acceptance: Ultra
technical lead, with conformance review of parser/evidence changes. This repair
supports the existing Step 1 objective and does not redefine its completion.
