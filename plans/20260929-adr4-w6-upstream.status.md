# Runtime upstream pilot: status

Created 2026-09-29. Status: DONE.
Task: [Runtime upstream pilot](20260929-adr4-w6-upstream.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Implemented the pinned, source-ID checked testfixture and execution-traced Tcl
pilot. Recorded 177 fresh typed native cases from 1,012 assertions in 12 passing
upstream files; eight files explicitly excluded. Native-only prefix minimization
preserves exact observations. Repeated extraction has identical case digest;
all frozen cases replay natively. Current model counts: 2 AGREE, 175 unsupported,
no disagreements or harness errors. See [pilot documentation](../docs/upstream-pilot.md)
and [manifest](../conformance/corpus-v1/manifest.json) for exact exclusions.

Validation: upstream harnesses all passed; extraction/frozen replay and native
recorder tests passed (5 tests, 3.10s); Nix tests.model passed (32 tests, 34.91s). `just conformance-upstream` refreshes into build/;
`just conformance-corpus` checks the frozen version. No merge is authorized.
