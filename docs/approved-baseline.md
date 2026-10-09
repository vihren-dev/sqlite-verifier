# Protecting approved requirements

A baseline file records the exact SHA-256 of approved Requirements,
Interpretation and every local Lean helper. Use it in the repository that owns
the approved requirements, so that a proof cannot pass because the requirements
changed. The `baseline.json` files in the examples are test fixtures for this
feature. They are not approvals.

Pass the appropriate protected file to `migration-check verify
--approved-baseline PATH`. The driver compares the complete snapshotted approved
source closure, including added, removed and changed dependencies, before compiling
any modules. Comparison uses the exact sealed source bytes that compilation consumes, including transitive
helpers; original files are not reread for compilation. A mismatch returns
`INPUT_ERROR` before any later Lean elaboration error (`UNVERIFIED`). Import-header
discovery still precedes comparison, so invalid or missing dependencies can fail
first. Matching baselines still require full compilation and the independent kernel
gate; omitting the baseline skips only this optional approval check. An optional
`schema.sql` SHA-256 entry also pins the exact authored starting SQL bytes. The shipped invoice and Atuin examples use that entry to bind their interpretations
to their schemas without maintaining a second schema declaration in Lean. Baselines
without this entry continue to protect reusable requirements across supplied
schemas. An `--artifacts` `inputs.json` export is inspectable evidence, not an
approval: copying it over a baseline does not authorize new requirements.

## Deliberate changes

A requirements change is a separate human review decision, not a proof repair.
The owner reviews the semantic changes and all affected local and library
dependencies. The owner checks that assumptions do not silently exclude states
or failures, and reviews the new hashes together with the source diff. There is
no automatic baseline refresh, and a successful compilation or proof does not
approve a changed baseline.
