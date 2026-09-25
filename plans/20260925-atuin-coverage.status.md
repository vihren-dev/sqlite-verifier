# Separate Atuin coverage scopes

Created:2026-09-25. Status:IN PROGRESS.
Tasks: [Atuin pilot](20260925-atuin-shell-migration.task.md) and
[bounded development resources](20260925-development-resources.task.md).

Root assigned the existing coverage-report integration: three payload cases and
two full-runner traces remain separate, with fresh wrapper stdout, exact fixture
identities/statuses/axioms/receipts and unknown discrepancy counts after failures.
The wrappers retain negative checks and existing native capture/runner suites
remain distinct. Shared commands execute each comparison once; CI retains raw
evidence. This does not change formal semantics or approved baselines.

Workspace merges rootd10e7eb3 with checked fullrunner6f2ff655. Integration engineer
owns only its CLI-harness recipe hook; this component owns coverage calls/artifacts.
Bounded failure/completeness tests and a real aggregate invocation are required
before independent review and checked commit. No checks completed yet.

## Checked implementation

The collector now invokes the complete payload and full-runner test wrappers
once each and validates their fresh stdout. Payload exposes the same checked
reports after its negative test; both receipt formats include exact target,
retained native trace and retained generated-proof SHA256 hashes. The validator
also checks case order/completeness, source/profile, explicit scope, metadata
identity, instrumentation label and exact theorem/allowed-axiom sets. No old
summary file is read as evidence. Each failed scope keeps matching/discrepancy
counts unknown. The previous3.51 evidence and theorem denominators are unchanged.

`just coverage` includes the distinct native capture/runner prerequisites. Shared
`test` no longer separately invokes payload comparison; the full-runner wrapper
also belongs only to the collector. Both existing negative checks remain inside
those wrappers. CI artifact paths now retain full-runner JSON and Lean files.

A single bounded tiny-environment batch passed the actual aggregate report:
existing native suites0.202s, payload wrapper2tests8.252s, full-runner wrapper
1test12.228s, all prior proof/parser/native/model evidence, and seven focused
coverage tests1.016s. Report is EVIDENCE_CHECKS_PASSED with separate payload3/3
and runner2/2 results. The shared-check dry run confirms one parser build, one
coverage call and one native capture/runner regression call, with no direct
Atuin model duplicates or nested Nix invocation. Independent review is pending.

## Independent acceptance

Component status:DONE. Ultra independently reviewed the final source and ran all
seven focused tests successfully in1.019s. Separate scopes, exact fresh receipts,
negative wrapper checks and once-per-wrapper shared integration were accepted.
The preceding actual aggregate result completes this component's acceptance.
Hosted integration, actual Atuin CLI gate coverage and owner pilot acceptance
remain separately owned; this does not mark Step1 complete.
