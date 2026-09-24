# Step 1 status

Created: 2026-09-24. Status: IN PROGRESS — not DONE.
Task: [Verified SQLite schema extensions](20260924-step-1-schema-extensions.task.md).

## Governing sources and roles

- [Engineering brief](../sqlite-migration-verifier-engineering-brief.md), rev 0.5.
- [Roadmap](../sqlite-migration-verifier-roadmap.md), proposal 0.1.
- [Team agreement](../sqlite-migration-verifier-team-guide.md), version 0.2.
- Workspace rules: `/Users/tzankomatev/work/AGENTS.md`.
- Product owner: Tzanko Matev, through the current conversation.
- Technical/formal lead: GPT-6 Astra Ultra; owns architecture and main integration.
- Conformance and integration engineers: GPT-6 Astra Medium; independent review.
- Coordinator: repository integration delegate, validation, durable records and owner sync.

Authors do not accept their own substantive changes. Isolated `jj` workspaces
live under `~/work`; the technical lead authorizes reviewed integration.
Initial task/status records preceded implementation. Original design documents
were saved by the owner and remain authoritative. Review found no specification
contradiction. Detailed component evidence lives in the other dated status files;
prior progress versions remain in `jj` history.

## Integrated implementation

The owner explicitly authorized the public repository and publication.
Origin: `git@github.com:vihren-dev/sqlite-verifier.git`.
Local root: `/Users/tzankomatev/work/sqlite-verifier`.
The pinned Nix/direnv environment uses Lean 4.33.0 and official SQLite 3.51.0,
with MIT license, retained upstream notices, and shared `just` commands.

| Component | Reviewed source/change | Evidence |
| --- | --- | --- |
| Foundation and CI | `2eb0b74a`, `3fac0a6a` | Pinned build/native smoke; workflow lint |
| Upstream parser | `2f5a83f5` | All 409 default grammar productions; 20 script regressions plus boundaries |
| SQL admission | `fe5f0ba9` | Complete CST traversal, source spans, 29 unsupported forms; native name comparisons |
| Formal core/contracts | `1f0c28bf2e2e` | Inductive/executable correspondence, all-outcome VC and arbitrary-data preservation |
| Original fixture slice | `c62b6d1d` | Three unchanged upstream assertions, inherited view/configuration/final state retained |
| Kernel gate/refutation | `f664abda`, `8f55b7f7` | Replay, protected declarations, exact target, transitive axiom audit, positive/negative proofs |
| Derived conformance | `6eaf2cb2` | Five native/model cases through production translation; false lost-row assertion rejected |
| Reusable examples | `2b134df2`, `874f0d36` | Two successful orders share approved meaning; schema refutation and separate allowed-failure policy |
| Isolated source compiler | `93313668` | Real sandbox checks, exact import closure, sealed stages and validated artifacts |
| Complete CLI | `c2288ede` | All 16 end-to-end invocations passed; profile diagnostics and inspection exports |
| Protected baseline CI | `faabe8b4` | Target-owned Git-object inspection; adversarial regression independently reproduced |

The CLI accepts all seven required inputs, generates/seals SQL and obligations,
and checks the independent kernel gate. `VERIFIED`, checked `VIOLATED`,
`UNVERIFIED`, `UNSUPPORTED`, and `INPUT_ERROR` remain distinct. Compiler success
alone never verifies. Optional baseline checks pin the complete approved Lean
source closure; hashes do not create human approval. SQL/profile bind each
invocation separately. Target-owned baseline checks and CODEOWNERS now have active remote workflow
policy and main-branch rules; only the named owner has audited bypass.

See [execution profile](../docs/execution-profile.md),
[semantic subset](../docs/semantic-subset.md),
[trust boundary](../docs/trust-boundary.md),
[source staging](../docs/source-staging.md), and
[kernel gate](../docs/kernel-gate.md) for exact guarantees and exclusions.

## Independent review and corrected defects

- SQLite column count and duplicate-name error precedence now match native evidence.
- All starting-schema dependencies are inspected; views/triggers/indexes are
  unsupported. Whole-script rollback is never inferred from one SQL file.
- Source aliases on case-insensitive filesystems and hardlinks cannot introduce
  candidate-only files into the approved closure.
- Artifact symlinks, including parent directories, and hardlinks are rejected
  before the unsandboxed parent reads compiler output.
- Blanket Nix-store access was removed. Runtime/input trees are read-only and
  disjoint from writable scratch; requested runtime aliases preserve those bounds.
- Containment tests cover approved writes, private reads, live host-network
  separation, credentials, output limits, timeout and Linux descendant cleanup.
- Linux denial errno differences were test defects, fixed without weakening
  production policy. The host-listener probe replaced an ambiguous closed port.
- Gate tests now invoke the absolute pinned compiler outside the repository,
  avoiding elan's unrelated default-toolchain lookup.
- Negative-proof selection checks the imported positive declaration before replay,
  so an unsafe positive cannot disappear and fall through to a negative target.
- Arbitrary custom readers still need human meaning/provenance review; a type
  signature alone cannot prevent a constant reader. Current additive primitives
  separately preserve every old physical row/cell; rebuilding is unsupported.

Per-file output limits are 16 MiB and returned streams 1 MiB. These are not total
scratch-disk quotas or VM isolation. Native correspondence is tested/documented,
not a proof of SQLite's C implementation.

## Validation state

- Local merged Lean build: 15 jobs pass, with only allowed foundational axioms.
- Local parser/native/model/gate/compiler/CLI suites pass under pinned Nix.
- CLI cases include changed SQL/interpretation, sorry, unproved premise, custom
  axiom, forged target alias, unsupported dependencies and changed approved helper.
- Hosted run `35990227855` (`b67516ab`) passed on x86_64-linux and aarch64-darwin,
  including real containment and kernel gate tests.
- Hosted complete-CLI run `35991726213` (`c2288ede`) passed macOS and failed
  Linux; the integration engineer is diagnosing the Linux failure before release.
- Baseline integration regression passes (0.906 seconds). Its workflow/code were
  independently reviewed and authorized by the technical lead; remote event-policy
  and branch rules are active (policy 5478, ruleset 23934665). Hosted unchanged
  baseline run 35992619415 passed; self-approval attack run 35992739741 failed as
  expected. Probe PR #1 was closed unmerged and its temporary branch removed.
- Original fixture results remain explicitly model-unchecked because their view
  dependency is unsupported. Five separately derived model cases do not change
  that status or imply general native refinement.

## Remaining engineering work

The lead is building installable native archives, offline Nix runtime transport,
extracted-package smoke tests, and a tag-triggered checked prerelease. Exact loader
roots must remain compatible with the narrowed sandbox. Coordinator is integrating
coverage reporting and observing hosted complete-driver checks. The Linux failure
was traced to Nix-patched Lean ELF loader paths; the lead is adding exact trusted
loader roots to source builds without granting the full Nix store. Release and
latest-platform evidence must pass before the engineering milestone is complete.

## Product-owner input and final acceptance

A real pilot needs its existing schema, actual creation/nullable-column migrations,
and the logical rows/fields/properties to preserve. A local project path or
sanitized SQL is enough to begin; the team can help formalize requirements.
Measure actual human authoring/review/repair effort separately from agent effort,
then obtain owner acceptance and update the roadmap before marking Step 1 DONE.

The initial pause incorrectly treated pilot evidence as a prerequisite to all
engineering. Work resumed; no requirement was waived. Synthetic examples enable
engineering but cannot replace the actual pilot. If no pilot is available, only
an explicit owner decision and roadmap change can replace that completion criterion.
Routine implementation choices continue autonomously; material product decisions
and genuine environment/specification blockers require an owner sync.

## Repository enforcement checkpoint

The technical lead authorized the main ruleset after review. GitHub's applied
branch-rules API confirms the three strict Actions checks, current code-owner
review and stale-review dismissal, plus deletion/force-push protection. Only
owner user 6329237 has audited bypass; no automation app does. This documentation
commit and subsequent reviewed initial engineering integration use that already
authorized owner access. No approved logical source or baseline changes here.

## Native loader integration

Lead change `101809c4` fixes the observed Linux compiler startup failure: Nix's
elan rewrites Lean's ELF interpreter to an exact store path. `just build` now
records loader roots from trusted native binaries; the same validated roots feed
compiler and gate sandboxes. Source and packaged layouts share that collector.
The full store remains inaccessible. Three focused regressions pass after root integration. The real isolated-compiler
recheck also passes; hosted Linux confirmation remains pending. The merged build succeeds on macOS (15 Lean jobs).

## Coverage reporting integration

Reviewed change `33278b91` adds a bounded report with separate proof, grammar,
documentation, fixture and native/model scopes. Root reproduced all five
failure/denominator regressions and the actual pinned report: six named theorem
probes, 409 default grammar productions, 20 grammar smoke scripts, three imported
assertion instances, and five derived native/model matches. These observations
are neither universal coverage nor native refinement. Missing/duplicate evidence
fails and leaves discrepancy counts unknown. Shared-command/CI artifact wiring
will land with the independently checked runtime packaging change.
