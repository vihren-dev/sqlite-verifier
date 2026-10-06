# Bundle attack parity and cold-run measurement

Status: IN PROGRESS. Harness validation has resumed; performance trials remain held.
Created 2026-10-06.

## Outcome

Every applicable attack in the current kernel gate suite has an independently
selected test through the bundle checker. Coverage includes a forged kernel
body, a wrong theorem, `sorry`, transitive axioms, changed protected declarations,
unsafe and partial proofs, a forged convenience target, a changed sealed profile,
approved source that substitutes the starting schema, and an unfinished
refutation. Environmental path checks and honest positive/refutation controls
remain explicit. Handcrafted hostile bundle records are tested where preparation
would omit the declaration or fail before a bundle reaches the checker.

A checked refutation returns 2 from the bundle checker, as from the current
kernel checker. The existing public CLI returns status `VIOLATED` with exit 1;
this task preserves that current CLI protocol. Each compilation-only case has a
specific nonapplicability reason at the checker boundary. Preparation still
executes Lean source and is not described as sandboxed.

The measurement harness compares `verify` with preparation followed by bundle
checking for the small success, checked refutation and Atuin examples on macOS
and Linux. It retains nine paired cold trials per example and platform, then
extends the same run to 25 pairs when the approved confidence test remains
unresolved. Existing raw trials are retained. It does not select a slowdown
percentage or time tolerance.

Each invocation starts a fresh process with empty proof, compilation and stage
caches. Both paths use the same installed runtime, protected inputs, timeout,
temporary filesystem and machine. Invocation order alternates between pairs.
Runtime installation and dependency downloads are outside timing; compilation
needed for the first invocation is inside it. Operating-system file caches are
not forcibly flushed. Their observed conditions, observation limits and
background load are recorded without inventing a cache state.

Each raw invocation retains its exact command, runtime and input identities,
platform, output status, exit code, monotonic wall time, stage times and artifact
identities. The combined preparation/checking wall time includes the whole path.
The report gives both path medians, the median paired difference and full ranges.
An interval for the median of `bundle path minus verify` uses ordered differences
and the binomial sign distribution with at least 95% coverage under the actual
nine-to-25 continuation rule. Fixed-size and simultaneous coverage are retained
separately; ties produce conservative bounds. A positive lower
bound means regression; a nonpositive upper bound means no slowdown. Otherwise
the nine-pair run extends to 25; an interval still spanning zero is unresolved.

Every result goes to the owner. A regression requires an owner decision. An
unresolved result prevents cutover. Slow trials are not removed because they are
slow; any invalid pair has a documented condition affecting the pair, and both
raw invocations remain available.

Source: [issue #30](https://github.com/vihren-dev/sqlite-verifier/issues/30).
Approved outcome and method: the product repository's
`plans/20261006-ready-task-proposal.md`, T06, and its owner review.
Related specifications: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md),
[data path](../docs/data-path.md), [kernel gate](../docs/kernel-gate.md).

## Acceptance

The attack matrix names every existing kernel case, its bundle-layer test or
explicit compilation-only reason, expected status and checker exit code. Actual
pinned compiler/exporter/checker tests reject applicable attacks and preserve the
positive and checked-refutation controls. Hostile records exercise the checker
without relying only on exporter-produced data. Tests have bounded processes and
retain useful failure diagnostics.

Pure tests cover exact confidence coverage, regression/no-slowdown/unresolved
classification, alternating order, nine-to-25 continuation, preservation of raw
pairs and refusal of changed identities or nonempty caches. Harness tests verify
real fresh child-process boundaries and monotonic accounting with deterministic
fixtures; they do not count as performance evidence. Stage observation calls the
existing verification/preparation/checking entrypoints rather than replacing
their acceptance flow.

Campaign persistence tests run the actual writer with explicitly synthetic path
observations. Completed and interrupted pairs retain their raw files, observed
paths and invalid conditions. A host change after a complete pair invalidates
the retained pair and campaign summary. Output refusals identify the output,
input root and next action. Interrupted metadata replacement retains the prior
complete JSON record. No incomplete pair acquires an invented duration.

The named launcher selects the shipped small success, checked refutation and
Atuin source directories through ordinary CLI arguments. It requires explicit
runtime, declared Python, new output and common timeout selections. Configuration
tests check current CLI parsing, expected statuses, full source roots, missing
selected inputs and fresh output refusal. Synthetic writer tests exercise the
entrypoint without running actual verification paths. The flexible `TrialSpec`
primitive remains available for manual arguments and source roots.

Actual performance trials wait for the final T05/documentation installed runtime
and coordinated idle hosts. The final evidence retains all raw trials on both
platforms and the owner's disposition where required. Until then this task is
IN PROGRESS and no timing acceptance is claimed.

## Constraints and relevant code

`tests/kernel_gate_test.py` is the current attack inventory. Its private compiled
fixtures and checker calls are independent of test selection order.
`tests/bundle_test.py` covers fewer attacks and already exercises the public
commands. Exporter omission of unsafe/partial declarations makes handcrafted
bundle coverage necessary. `BundleChecker.lean` reconstructs generated inputs,
compares protected declarations and shares the target/axiom checks in `GateCore`.

`migration_check/cli.py`, `prepare.py`, `bundle.py`, `compile.py`, `contract.py`
and `stage_store.py` own the actual command paths and caches. The older latency
experiments include warm iterations and are not the approved nine-pair protocol.
Stage measurement must follow current callers and distinguish stage durations
from complete subprocess wall time.

No `verify` cutover, old checker deletion, compatibility API or second replacement
path is part of T06. Checker/export/approval fixes require the checklist's final
owner review. Keep existing trust assumptions and supported SQL/profile meanings.
The exporter/upgrade base is reviewed `07dc71b3`; the public baseline is
`29d2ed7a`. Both remain intact. Files stay below 200 lines, and each checked
unit has a status update, Jujutsu commit and independent review.

## Current checkpoint boundary

The existing attack tests, confidence policy and cold-path recorder are checked
within the scopes listed in the status file. The campaign writer has bounded
persistence tests with synthetic observations; separate real-child tests cover
subprocess boundaries. The named-case launcher has bounded configuration and
synthetic writer checks. Its installed-runtime execution contract is not yet
accepted. Ordinary integrated/Nix infrastructure checks and actual macOS/Linux performance trials
remain incomplete. Work continues on the existing harness; performance trials
remain held and this task is not DONE.
