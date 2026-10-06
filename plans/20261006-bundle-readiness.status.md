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
- 2026-10-06: Statistics review `395b748c` confirmed the arithmetic and tie
  calculation, with five `should` findings and no `must` findings. Documented
  the predeclared counts, ranks and named 95% requirement, clarified coverage
  for caller-supplied ranks, and added received count/index/type diagnostics.
  Added invalid-rank/count tests at both looks. Resolved
  `20261006T164839Z-395b748c#1` through `#5`. All 30 statistics checks pass under
  the 30-second bound. Three new observer checks also pass in the working copy;
  their feature will be recorded separately.
- 2026-10-06: Confidence-policy cleanup `6df37baa` passed independent review
  with no findings. Added a stage observer that runs the actual installed
  launcher under its pinned isolated Python, retaining source-hashed nested
  spans from that invocation. It does not replace driver functions or change
  reports/exits. Four bounded child/current-caller tests preserve positive and
  `VIOLATED` protocols, prove fresh PIDs and bind spans to the same external
  monotonic wall interval. The combined 34 pure/child checks pass in 0.34 seconds
  (30-second bound). These are harness fixtures, not performance evidence.
- 2026-10-06: Observer review `461a4186` found three `should` findings and
  no `must` findings. Documented the selected stage policy, named external
  process-role classification, and added same-process dependency/compile/checker
  spans plus exception-ending stage coverage. Resolved
  `20261006T170020Z-461a4186#1` through `#3`. All 35 statistics/observer checks
  pass in 0.50 seconds (30-second bound). Public reports/exits remain unchanged,
  and each exception path leaves zero active stage frames. No performance trial
  or acceptance cutover occurred.
- 2026-10-06: Observer process-role cleanup `3863ae85` passed independent
  review with no findings. Extracted the unchanged private kernel fixture and
  exact 12-case proof-attack inventory into flat helpers for both checker suites.
  Updated the kernel target's explicit Nix inputs. All 19 existing kernel cases
  pass against the cached reviewed Lean 4.34.1/T02 Darwin runtime (120-second
  suite bound; each compile/check remains bounded). No actual timing trial ran.
- 2026-10-06: Shared fixture/inventory checkpoint `5062c3e9` had no `must`
  findings. Its two `should` findings described the second caller before it
  existed. Added that caller and resolved `20261006T171202Z-5062c3e9#1` and
  `#2`. All 23 independently selected bundle attacks pass in 29.08 seconds
  against the cached reviewed T02 Darwin runtime (150-second bound). Actual
  exports cover applicable source attacks and controls; handwritten valid
  records cover forged bodies, protected substitutions, unsafe/partial proofs
  and hostile headers. Refutation returns direct checker 2; public CLI stays 1.
  The review matrix explains why the old compiled-`SqlInputs` profile mutation
  does not apply directly and tests the corresponding changed profile record
  against the actual frontend request. No checker/exporter source changed.
  Added exact shared fixture inputs to both Nix suites and the new bundle
  caller to its ownership manifest. All 37 pure inventory/statistics/observer
  checks pass in 0.51 seconds (30-second bound). Nix infrastructure and ordinary
  integrated checks remain to run after coordinated assembly; full model is
  owner-held and timing trials remain held for the final runtime.
- 2026-10-06: Attack checkpoint `5ae0e253` passed review with no `must`
  findings and two `should` findings. Reused current preparation's export roots
  and protected base constant, and gave the fixture header its actual library
  import. Clarified the complete malformed-header test scope. Resolved
  `20261006T172148Z-5ae0e253#1` and `#2`. All 23 direct bundle checks pass again
  in 28.68 seconds under the same 150-second bound. No trusted/checker code or
  public protocol changed, and no performance trial began.
- 2026-10-06: Attack export cleanup `791ec7e6` had no `must` findings.
  Named and documented the four fixture-only compiled-module omissions,
  including why fixture-owned `SqlInputs` differs from production preparation
  and why handwritten protected records remain necessary. Resolved
  `20261006T172547Z-791ec7e6#1`. The omitted set and behavior are unchanged from
  the passing 23-case checkpoint; the 37 pure checks remain passing.
- 2026-10-06: Fixture-boundary documentation `d4441c8d` had one `should`
  finding and no `must` findings. Named KernelCase, BundleCase.export and
  production export_bundle directly and stated which definitions each owns
  or omits. Resolved `20261006T172800Z-d4441c8d#1`. Behavior and the previously
  checked omitted set are unchanged; this is a documentation correction.
