# Nix test targets status

Created: 2026-09-28. Status: DONE.

Contract: [task](20260928-nix-test-targets.task.md).

`build-support/tests.nix` declares independent kernel and native/model pytest
targets with explicit source and runtime dependencies. `just test` builds these
with sandboxing enabled and fallback disabled, then runs all other source cases
in one pytest invocation. Direct pytest/test-cases always executes selected tests.

Removed the source/independent Python suite runners, unit-result validator and
unitChecks derivation, aggregate coverage report and receipt validation, and
obsolete tests of those mechanisms. Substantive grammar, named-proof, model,
parser, CLI, sandbox and installed-runtime assertions remain. Pytest reports are
diagnostics, not a second pass/fail gate. Existing benchmark tooling reads the
new cached test outputs rather than unit receipts or coverage.json.

CI now restores compatible Nix store outputs by default using native action
keys; Nix derivation identity controls reuse. Only successful main jobs save
caches. Tests needing the production host sandbox or Nix daemon still run fresh.
Cheap unit tests also rerun; caching targets the costly Lean work.

Validation on aarch64-darwin:

- Kernel target: 19 passed, 49.33 seconds.
- Model target: 6 passed, 24.10 seconds on final sources.
- Warm reuse of both targets: 1.20 seconds, no pytest execution (measured before
  the final model comment edit, which correctly invalidated only that target).
- Seven real Nix dependency/failure regressions passed: declared edits invalidate
  only dependent targets, unrelated test edits preserve both, failed pytest
  produces a failed derivation. A separate sandbox probe confirmed that the
  undeclared checkout was inaccessible.
- One host pytest invocation: 303 passed, 136 subtests passed, two deselected,
  246.01 seconds. Deselections are the two link checks affected by the three
  pre-existing uncommitted draft documents. All other documentation links pass.
- Six installed-runtime checks passed through direct pytest against the existing
  offline archive (36.50 seconds). Production runtime bytes did not change.
- CI orchestration regression tests: six passed. Pytest harness: 15 passed.
- Both x86_64-linux test derivations evaluate successfully. Native Linux execution
  and hosted cache transfer/performance remain for CI; neither is claimed here.
- Active collection: 336 cases, including 330 source and 19 installed identities
  (13 Atuin identities are shared). 73 obsolete cases retired, seven added.

Unrelated drafts docs/0003-component-research.md,
docs/adr-0002-compile-project-cache.md and docs/adr-0003-agent-proof-preparation.md
remain untouched and uncommitted. The user explicitly superseded ADR 0001's
unit-cache/coverage runner design; historical documents now link to current behavior.
