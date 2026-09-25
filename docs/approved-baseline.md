# Protecting approved requirements

The examples carry CLI-compatible `baseline.json` files in each `approved/`
directory. They record the exact SHA-256 of Requirements, Interpretation and every
local Lean helper. Two maps describe synthetic engineering requirements; the
proposed Atuin map describes the actual application's pilot contract. None of
these engineering snapshots substitutes for human approval of changed or new
requirements. The approved library and verifier implementation are separate
trusted code and require their own review.

Pass the appropriate protected file to `migration-check verify
--approved-baseline PATH`. The driver compares the complete compiled approved
source closure, including added, removed and changed dependencies, before accepting
a proof. An `--artifacts` `inputs.json` export is inspectable evidence, not an
approval: copying it over a baseline does not authorize new requirements.

## CI boundary

The `Approved baseline` workflow exposes the check **Protected approved baseline**.
It uses `pull_request_target`, read-only repository permission, and checks out the
exact target-branch commit. It fetches the candidate commit as Git objects only.
The target branch's Python checker reads those blobs; it never checks out candidate
files, imports candidate Python, runs candidate Lean, enters its Nix environment,
or loads its build configuration. Full lowercase commit hashes are validated and
passed as subprocess arguments. A PR cannot change its checker or manifest to
approve itself.

The target manifests pin the exact set of `.lean` files under the ordinary,
allowed-failure and Atuin approved directories. This conservatively includes unused helpers as well as the
actual import closure; all application dependencies should live within the
reviewed approved tree. The separate driver check uses the exact compiled closure.
Any changed baseline, changed source, added source, removed source or source
symlink fails CI. A newly introduced workflow cannot enforce itself before it
exists on the target branch; bootstrap requires direct owner review.

## Deliberate changes

A requirements change is a separate human review decision, not a proof repair.
The owner reviews the semantic changes and all affected local/library dependencies,
checks that assumptions have not silently excluded states or failures, and reviews
the resulting hashes alongside the source diff. An intentionally updated baseline
and its source changes may land together only after explicit owner approval and a
recorded maintainer bypass of the expected failing drift check. There is no
automatic baseline refresh or approval inferred from compilation or successful
proofs. Ordinary migration-only PRs must pass without a bypass.

The proposed Atuin baseline protects Requirements, Interpretation, AtuinSchema
and AtuinCatalog. Adding this third protected root and updating the two existing
sets of source hashes requires the owner review recorded in the
[pilot packet](atuin-pilot-review.md). Until that review is complete, these
changes remain proposed and must not be integrated into public `main`.

GitHub may disable `pull_request_target` through workflow event policy on public
repositories. Confirm this narrowly scoped, data-only workflow is allowed before
calling the check enforced; see GitHub
[workflow execution protections](https://github.blog/changelog/2026-09-17-workflow-execution-protections-in-github-actions-generally-available/)
and [safe target-event usage](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).

The public repository's [main ruleset](https://github.com/vihren-dev/sqlite-verifier/rules/23934665)
was activated and read back on 2026-09-24. Its rules are:

- Require PRs, one current approving review, code-owner approval, approval of the
  latest push by another actor, and resolved review threads. Dismiss stale approvals.
- Require `Protected approved baseline` plus both platform build/check jobs,
  and require branches to be up to date before merging. Retargeted PRs rerun the
  baseline workflow; a stale target-branch baseline must not authorize a merge.
- Only `@tzanko-matev` (user ID 6329237) has an audited maintainer bypass. No
  automation app or general repository role has bypass. Deletion and force pushes
  are blocked for ordinary contributors. Record the reason for each bypass.
- Protect `.github/CODEOWNERS`, workflows, the baseline checker, trusted compiler,
  parser, proof gate, formal library and toolchain pins under `@tzanko-matev`.

The three status checks are bound to GitHub Actions (app ID 15368), and
[workflow event policy 5478](https://github.com/vihren-dev/sqlite-verifier/settings/actions/rules/5478)
allows `pull_request_target` only for this baseline workflow. CODEOWNERS requests
are enforced by the ruleset. Human owners still review changes to the check's
trusted target-branch implementation.

[Probe PR #1](https://github.com/vihren-dev/sqlite-verifier/pull/1) was closed
without merging. Its unchanged baseline
[passed](https://github.com/vihren-dev/sqlite-verifier/actions/runs/35992619415);
its next candidate changed approved source, rewrote its manifest, and replaced
the candidate checker with unconditional success, yet the trusted workflow
[rejected it](https://github.com/vihren-dev/sqlite-verifier/actions/runs/35992739741).

Initial engineering integration uses the owner's already-authorized repository
access and records technical-lead review in the dated status files. This
maintainer bypass is not product-owner approval of changed logical requirements;
such changes still require the explicit semantic review described above.
