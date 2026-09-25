# Atuin case study and acceptance review

Accepted by product owner Tzanko Matev on 2026-09-25: “As far as I am concerned,
I approve the current state.” This closes Step 1 product acceptance. Hosted full package checks now pass on both platforms in
[run36138251243](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36138251243).
Publication of v0.1.0 remains the final release gate, tracked in
[the release task](../plans/20260925-step1-release.task.md).

## Case study and accepted guarantee

The owner selected Atuin as the real, source-backed case study and guided the
business-model refinement. The [Atuin example](../examples/atuin/README.md) links
the exact upstream schema, nullable shell-column migration and application field
semantics. Its approved model describes old histories without anticipating shell
or prescribing a target schema. For every admitted database, verification proves
successful modeled execution and recovery of the same complete old history list
from resulting storage, including all protected fields and multiplicity.

Schema and migration SQL are the product boundary. The example does not import or
execute Atuin or SQLx. SQLx invocation and catalog maintenance remain trusted;
there is no framework certification. The conservative decoder domain, fixed
execution assumptions and exclusions are explicit in the example. Recoverability
does not establish new-feature correctness, application-query compatibility or a
formal correspondence with SQLite C or the Rust decoder.

## Evidence and human involvement

Agents authored the formalization and executed the public CLI checks. The owner
reviewed and refined the intended business meaning and accepted the current
state. The final local full `just check` at implementation `0c5bb79e` passed in
the pinned aarch64-darwin environment, including two positive Atuin CLI cases and
eleven negative cases. Both shell and a differently named nullable column verify
against identical approved hashes. Negative cases reject stale proofs, changed
protected inputs, unsupported default semantics, lost histories, erased commands,
missing representation conditions and unfinished proofs. Rejection diagnostics
are checked and are not reported as formal refutations.

Independent conformance review examined admission, complete decoding, result-only
recovery and all modeled outcomes. Three native fixtures provide additional finite
storage evidence; some deliberately lie outside the formal decoder domain.
See [preservation status](../plans/20260925-business-preservation.status.md) for
validation scope. Earlier preview CI and runner-capture evidence do not establish
correctness or cross-platform packaging of these revised inputs.

Human authoring, review and repair time, the previous workflow's effort, and agent
cost/retry totals were not measured comparably. No productivity improvement or
independent human execution is claimed. Acceptance is qualitative and explicit;
it does not fabricate missing measurements or demonstrate adoption or willingness
to pay. No additional pilot, project or framework integration is required for
this owner-accepted Step 1 scope. Step 2 remains a future roadmap proposal.
