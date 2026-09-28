# Cache expensive pytest suites with Nix

Created: 2026-09-28. Status: DONE.

Expensive hermetic suites run as independently cached Nix derivations, using
ordinary pytest and explicit source, toolchain and runtime dependencies. Kernel
replay and native/model comparison are initial targets. Changed declared inputs
invalidate the relevant target; unrelated source files do not. Cache misses must
run with Nix sandboxing enabled, without silently falling back to unsandboxed
execution. Tests requiring the actual host sandbox or Nix daemon remain host tests.

`just test` builds these targets and runs the remaining source tests with one
pytest invocation. Direct pytest remains available to rerun any suite. Pytest's
exit status is authoritative; remove aggregate coverage gates, Python suite
orchestration and cached-unit receipt validation. Preserve substantive parser,
proof, model, CLI, containment and installed-runtime assertions.

CI restores compatible Nix store outputs by default and lets Nix derivation
identity decide reuse. No custom test-result cache or new service credentials.

Validation includes real sandboxed cold/warm target runs, dependency mutation
checks, a failing test target, host regression tests and direct pytest selection.
Record measured reuse, remaining host costs and platform validation limits.
