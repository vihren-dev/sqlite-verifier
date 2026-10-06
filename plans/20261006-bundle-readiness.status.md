# Bundle readiness status

Status: IN PROGRESS. Created 2026-10-06.

Task: [bundle attack parity and cold-run measurement](20261006-bundle-readiness.task.md).
Source: [issue #30](https://github.com/vihren-dev/sqlite-verifier/issues/30).
Specifications: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md),
[data path](../docs/data-path.md), [kernel gate](../docs/kernel-gate.md).

## Progress

- 2026-10-06: Read the approved product T06 card and owner review before work.
  Created isolated Jujutsu workspace `bundle-readiness` from reviewed exporter/
  upgrade `07dc71b3`, then merged published main `29d2ed7a`. Only the review
  journal conflicted. Preserved all 63 raw lines and both parent orders; no
  reviewed feature commit was rewritten.
- Read issue #30 (open, no comments), the full kernel attack inventory, existing
  bundle tests and both drivers. The direct checkers return 2 for a checked
  refutation; both public CLI paths currently report `VIOLATED` with exit 1.
  The task states this boundary explicitly and preserves the public protocol.
- Current reports do not expose stage timings. The older stage-timing experiment
  references a replaced parser caller and runs in process. New observation must
  follow current command callers while preserving fresh process boundaries and
  acceptance behavior.
- Attack parity and a tested measurement harness are authorized now. Actual
  performance trials wait for the final installed runtime and idle-host
  coordination. T06b cutover is outside this task. No performance trial or
  owner-held full model gate has started.
