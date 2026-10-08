# Integrated model package acceptance, 2026-10-09

The correction preserves original root lookup for each requested package spelling. Distinct origins or missing siblings require a case-sensitive workspace when an insensitive workspace cannot represent them. The incoming application-key code, examples and build targets use the moved model namespace.

Implementation snapshot `3e5e4a10` passes 605 native tests across all nine suites on each platform, with no failures, errors or skips. Both platforms pass 115 infrastructure tests and 26 actual offline installed package and Atuin tests. Linux source checks pass 461 tests and explicitly skip two optional reviewer-tool checks. The original Linux archive, verified against its independent hash, retains raw logs and all nine XML receipts. macOS originals are retained as lossless gzip files.

Accepted main `2954eb7a` adds the cached core reference and ADR 0009 testing rules. Resolved the reference builder for both package roots. Current macOS source validation passes 474 tests and infrastructure validation passes 115 tests. Evaluated Nix identities prove that its runtime and all nine native suite outputs match the passed outputs. The real cached reference base builds 29 public modules and applies 11 corrections for the documented doc-gen4 issue. Tests check our arguments, source links and correction; the build follows main's removal of the second inventory and dependency-output validation.

The earlier complete reference receipt is historical evidence from the original snapshot. It is not the current reference validation policy. The failed initial application-key run and the 900-second aggregate timeout are retained. The resumed macOS command reuses six completed suites and finishes the remaining three with unchanged per-test and suite limits. No timeout or aborted target is counted as a pass.

Historical plan files and every retained review-journal sequence remain unchanged. Only this task's active plan records are updated. Final owner review of the integrated published head, its codec, trusted roots, target, export and checker changes remains required. The protected-baseline owner gate is not waived.
