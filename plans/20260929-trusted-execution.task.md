# Trusted execution and cached Atuin tests

Created 2026-09-29. Status: DONE.

The source verifier assumes trusted Lean execution. It does not implement OS
sandboxing or claim to contain hostile tactics. Callers protect the environment,
approved inputs and result channel; future isolation belongs to an integration
layer after ADR-003. Proof replay, target reconstruction, approval checks and
source snapshots retain their behavior. Processes retain deadlines and bounded
output with explicit toolchain paths.

Remove OS sandbox code, dependencies, runtime manifests, capability probes and
obsolete isolation tests. Atuin behavior runs as a separate Nix pytest target
with declared inputs and cached success. `just test` includes it; `just test-atuin`
selects it independently. Nix build sandboxing remains enabled.

Validation covers process limits, compilation/CLI/approval regressions, all Atuin
cases inside Nix, warm cache reuse, dependency invalidation and packaging.
Docs must distinguish trusted execution from future hostile-input containment.
