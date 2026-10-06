# Lean 4.34.1 final owner review

Created 2026-10-06. Status: AWAITING OWNER REVIEW.
Task: [runtime upgrade](20261006-lean-4-34-1-upgrade.task.md).
Status: [acceptance record](20261006-lean-4-34-1-upgrade.status.md).

Checklist [R8](../docs/review-checklist.md) requires owner review of the
two kernel replay chains and the exporter pin. Claude identified these
three requirements in review `20261006T091345Z-e2703279`; it did not report
a defect in them. The diagnostic findings are fixed and the last corrective
commit, `d065c8b4`, passed independent review with no findings.

## Changes for acceptance

[ProofChecker.lean](../ProofChecker.lean) and
[BundleChecker.lean](../BundleChecker.lean) now call
`Environment.ofKernelEnv (← env.toKernelEnv.replay constants)`.
This is the exact implementation of Lean 4.34.1's deprecated
`Environment.replay` wrapper in `Lean/Replay.lean`, lines 194–197.
`Kernel.Environment.replay` sends declarations to the kernel and checks
postponed constructors and recursors. `Environment.ofKernelEnv` retains
that kernel environment as its private and public base. Both gates pass
the result to the unchanged target comparison and axiom audit.

[lean4export.nix](../build-support/lean4export.nix) now pins v4.34.0 at
`076e8e57707e813375e8f9da8bf989799ace9680`, built with Lean 4.34.1.
The existing skip-trusted patch retains its policy. Its context includes
the upstream guard that omits unsafe or partial declarations when unsafe
export is disabled. The acceptance gate still audits the replayed target
and its dependencies. Exporter replacement belongs to a separate task.

The official toolchain archive digests, patched dependency digest and
runtime paths are recorded in the linked status and platform reports.
The protected inputs, axiom policy and verification propositions retain
their meanings.

## Completed checks

| Check | macOS arm64 | Linux amd64 |
| --- | --- | --- |
| Native runtime, library, gates and exporter | Passed | Passed |
| Source checks | 321 tests and 28 subtests passed | 319 tests and 28 subtests passed; two optional Codex/Claude cases skipped |
| Full Nix targets | All seven passed | All seven passed |
| Model cases | 322 passed; one expected Tcl capture skip | 322 passed; one expected Tcl capture skip |
| Separate pinned upstream target | 58 passed | 58 passed |
| Nix infrastructure | 68 passed | 68 passed |
| Offline extracted installation | 21 passed | 21 passed |
| Small, refutation and Atuin exporter baselines | VERIFIED, VIOLATED, VERIFIED | Same statuses and identical bundle bytes |

The internal checker exits are 0, 2 and 0. The CLI exits are 0, 1 and 0.
The owner-authorized PATH lookup passes the actual process-group test on
both platforms. The later runtime diagnostic regression passes locally;
the recorded platform snapshots precede that diagnostic wording change.

[Darwin report](../reports/20261006-lean-4341-upgrade-darwin.json) and
[Linux report](../reports/20261006-lean-4341-upgrade-linux.json) identify
JUnit results, native archives, exact inputs and exporter baselines by
SHA-256. Historical corpus v1–v5 is unchanged.

## Remaining acceptance

Owner acceptance of the replay chains and exporter pin remains open.
Hosted CI must pass for the final revision on macOS 14 and Ubuntu 22.04.
The Linux native checks above ran on NixOS. Publication of the prepared
v0.1.2 release follows both gates. No tag or release is published yet.

## Owner disposition

Pending. Record the owner's response here and resolve the three R8
findings through `just review-resolve` after acceptance.
