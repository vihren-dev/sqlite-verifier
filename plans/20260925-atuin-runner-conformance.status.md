# Complete finite SQLx runner comparison

Created: 2026-09-25. Status: IN PROGRESS.
Task: [Atuin shell migration](20260925-atuin-shell-migration.task.md).

The payload comparison remains separate. This unit resumes preserved WIP64062d08
after the approved development-resource repair, using explicit `path:./nix#capture`
only. Runner interfaces are unchanged from checked formal8ca23cd5.

Normal success and a schema-preserving authorizer-instrumented timing failure now
pass complete concrete ProfileExecutes, readiness and before-conformance checks.
Actual physical metadata/statistics rows are retained, alongside independently
expected history cells. Exactly three named theorems are audited against
propext/Classical.choice/Quot.sound. The instrumented failure is explicitly not
evidence of failure under the unmodified native configuration.

Locked offline Cargo build passed1.92s and all18 Lean library jobs passed. First
resumed trace proofs exposed tactic reduction issues (Bool comparisons and the
concrete payload step), corrected without changing semantics. Both traces now
kernel-check. A bounded negative bookkeeping-version regression and final
existing native/payload checks are pending. Independent lead review follows.

## Final checked trace unit

The complete normal and authorizer-instrumented traces pass, and altering the
inserted version in the expected final metadata is rejected. Reports retain raw
trace/proof/target hashes, exact theorem audits, physical metadata rowids1–6
before and1–7 afterward, and statistics counts (six stat1 rows, zero stat4 rows
in these particular observations). Empty stat4 is the actual captured state,
not an omitted table. The model checks its unchanged definition and full rows.

The callback denies exactly the intended elapsed-time UPDATE. The harness keeps
one acquired connection to ensure that hook applies, calls real Migrator, and
clears caches only following success, matching Atuin's early-error ordering.
It does not run the Atuin binary/background compactor. Failure instrumentation
remains distinct from the unmodified runner success evidence.

Final corrected offline Rust build passed2.11s; both existing native suites
passed0.202s; full-trace plus negative suite passed14.376s. The earlier unchanged
payload suite passed two tests in8.619s, including exact axiom audit negatives and
false history expectation rejection. Every tool call used the reviewed tiny
capture environment; no full-workspace Nix entry or cleanup occurred.

Ultra source review accepted the generator, native hook, connection harness,
negative test and honest scope. Independent full-trace reproduction is pending.
Root owns shared command/CI/coverage wiring. The canonical entrypoint is
`timeout 240 python3 tests/conformance_atuin_runner_model_test.py`; JSON stdout is
published only after the positive traces and negative metadata check pass.

## Independent acceptance

Component status: DONE. Ultra independently reproduced the entire full-trace and
incorrect-version suite in15.553s using the existing binaries and reviewed tiny
environment, and accepted the source. The standalone entrypoint additionally
checks the exact seven-file migration inventory and every original SHA256 pin
before observation; its cheap actual inventory/hash check passed. This addition
does not change generated proof obligations or native execution.

This completes the bounded finite-runner evidence component, not the universal
Atuin VC, shared coverage integration, real-pilot owner review or Step1 overall.
