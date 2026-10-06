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
- 2026-10-06: Planning/base checkpoint `493e049a` passed independent review
  with no findings. Added exact integer-nanosecond median bounds. The approved
  continuation needs joint coverage: closest fixed-size 95% intervals at both
  looks would jointly cover only 92.7211%. Predeclared ranks are 2–8 at nine and
  7–19 at 25, retaining the initial nine. Fixed-size coverages are `123/128` and
  `8265855/8388608`; simultaneous coverage is `1994151/2097152` (95.0885%).
  Root confirmed this interpretation before observations; no time tolerance was
  added. All 17 pure tests pass in 0.03 seconds (30-second bound), including
  independent sign counts, conservative trinomial ties, exact rank bounds,
  one-nanosecond decisions, zero and invalid evidence. No performance run began.
