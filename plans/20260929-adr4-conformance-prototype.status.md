# ADR 0004 conformance prototype status

Created 2026-09-29. Status: DONE (W1–W2).
Historical completion record for the initial prototype. Subsequent review fixes
and current evidence are tracked in [review correction status](20260929-adr4-review-fixes.status.md).
The build-wide DQS setting and throughput measurement below describe the original
prototype and are superseded by that review.

Task: [outcomes and checks](20260929-adr4-conformance-prototype.task.md).
Specification: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).
Evidence: [measured report and source hashes](../reports/20260929-adr4-prototype.json).

## Completed work

- Dedicated jj workspace `adr4` at `../sqlite-verifier-adr4`, based on `8c4e5ad4`
  (ADR revision `acadc4cc`). Original workspace unchanged.
- `907a251a`: task and status records; Markdown checks passed.
- `6e26bd8d`: production `advance` trace and universal final-observation equivalence
  to `runSql`; focused kernel observations and the original model suite passed.
- Final workspace refresh inherited two unrelated Attic CI planning documents
  from the original workspace. The preceding changes rebased to `36665e02` and
  `7402e5bd`; all 75 recorded implementation hashes still match the tested sources.
- W1–W2 completion: versioned structural codec, initial fixture records, the sole
  Lean classifier, its Boolean proof predicate and unsupported-case lemma;
  persistent pinned native acquisition; compiled JSON-lines runner; native/kernel
  regressions; test-only Nix runtime and dependency checks; executable commands
  and documentation. Five native records are frozen in `conformance/cases/`.
- Existing fixtures retain rowids, cells, metadata, expected native diagnostics,
  exact model error positions/categories and frontend schema outcomes. Separate
  old equalities were replaced with `checkCase` proofs only after live parity.
  `model_native.py` was retired; imported upstream fixtures remain unchanged.

## Requirement evidence

| Requirement | Evidence |
| --- | --- |
| Shared comparison and decoding | `ConformanceCase.lean`, `ConformanceJson.lean`, `ConformanceRunner.lean`; five frozen cases round-trip through the compiled decoder and receive kernel proofs. |
| Production execution and admission | `ConformanceTrace.trace_final`, `admitted`, `unsupported_not_checked`; transaction, data-domain and invalid-definition tests. |
| Faithful native observation | `native_connection.py` and `native_trace.py`; real pinned-library configuration checks, visible/committed snapshots, exact byte/REAL reads and populated wide-table tests. |
| Failures do not become agreement | Wrong traces and lost rows fail kernel agreement; a real exclusive lock yields HARNESS_ERROR; malformed versions/bytes/JSON fail closed. |
| Actual model fault detected | Test-local copy of production execution drops INSERT; compiled and kernel evaluation report disagreement at statement 1. |
| Proof policy | Generated axiom audits and three forbidden-family unit probes, including `_native`; no native proof oracle. |
| Reproducibility and rollout | `just conformance --repeat 3 --prove`; frozen native records; separate conformance build; same tests.model in just test; source-identity tests cover new inputs. |

## Validation

- `just test` passed: 264 host cases, 28 host subtests, and all four Nix suites
  (19 kernel, 13 CLI, 12 Atuin, 18 model). The process-cleanup host test needed
  execution outside the agent sandbox because `/bin/ps` was denied; Nix build
  sandboxing remained enabled.
- The final frozen-record model derivation passed 18 tests in 24.19 seconds.
- Nix dependency/flake-equivalence and Markdown checks passed 19 tests. Both
  aarch64-darwin and x86_64-linux target graphs were evaluated; native execution
  evidence is aarch64-darwin only.
- Three repeats of the five authored cases produced 15 AGREE results and 42 native
  observations in 1.95835 seconds (7.65949 cases/second), including parser, native
  snapshots and compiled classification, excluding kernel proof time. All five
  emitted regression proofs were checked in that run. This is a warm local DDL
  workload, not an estimate of generated or transactional corpus throughput.

## Implementation constraints retained

The function-valued Database representation and production evaluator are unchanged.
Observation uses a small kernel-reducible insertion sort; its quadratic ceiling
is documented. The shared library now explicitly compiles with DQS=0, matching
its shell. Primary error codes reflect the model's granularity; extended codes
are retained diagnostically. The conformance executable is not shipped as a new
verifier command. No universal SQLite refinement is claimed.

## Next decision

W1–W2 are DONE. W3 generation, W4 regression harvesting, W5 general laws,
W6 upstream mining, W7 coverage and independent-kernel replay are not implemented
by this bounded prototype. The ADR explicitly leaves the later pipeline outside
this approval; the owners must review W2 evidence before authorizing its next stage.
