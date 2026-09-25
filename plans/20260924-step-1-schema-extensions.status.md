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
| Bounded coverage | `33278b91` | Five failure/denominator regressions; refreshed independent scopes and explicit exclusions |

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
- Hosted run `35998140680` (`c840b0434186`) passes on both declared platforms,
  including containment, complete CLI, native packaging and installed smoke tests.
- Baseline integration regression passes (0.906 seconds). Its workflow/code were
  independently reviewed and authorized by the technical lead; remote event-policy
  and branch rules are active (policy 5478, ruleset 23934665). Hosted unchanged
  baseline run 35992619415 passed; self-approval attack run 35992739741 failed as
  expected. Probe PR #1 was closed unmerged and its temporary branch removed.
- Original fixture results remain explicitly model-unchecked because their view
  dependency is unsupported. Five separately derived model cases do not change
  that status or imply general native refinement.

## Engineering release checkpoint

Native archive building, offline installation, shared coverage reporting and a
checked prerelease workflow are integrated. Full hosted checks and extracted
archive installation pass on both platforms at `c840b0434186`, run
[35998140680](https://github.com/vihren-dev/sqlite-verifier/actions/runs/35998140680).
Tag `v0.1.0-rc.1` names that exact checked commit. Its independent version-tag
workflow passes both platform checks and publication. The
[public prerelease](https://github.com/vihren-dev/sqlite-verifier/releases/tag/v0.1.0-rc.1)
has two checked native archives and matching checksum files. Exact hashes and
publication evidence are in [packaging status](20260924-runtime-packaging.status.md).

## Product-owner input and final acceptance

A real pilot needs its existing schema, actual creation/nullable-column migrations,
and the logical rows/fields/properties to preserve. A local project path or
sanitized SQL is enough to begin; the team can help formalize requirements.
On 2026-09-25 the owner requested a popular open-source pilot instead. The
[candidate research](../docs/pilot-candidates.md) recommends Atuin's actual history
migration, while identifying existing constraints, indexes and runner behavior
outside our current subset. Pilot selection and compatibility scope need owner
input; no semantics or original requirements were changed by the research.
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

## Native packaging integration

Reviewed author change `50cbec70` adds installable archives, full Lean runtime,
signature-checked offline Nix cache, pinned isolated launcher and GC roots. Author
and independent conformance reviewer tested exact macOS archive SHA-256
`8637aa7b94853511cee995b082280e7333d370d0c70a2b374663c470724170aa`:
installation into paths with spaces, actual VERIFIED/VIOLATED/UNSUPPORTED cases,
and poisoned ambient runtime variables all pass. Installer races and URI paths
have bounded regressions. The package is about 972 MiB and is not claimed to be
bit-for-bit reproducible. Nix and platform kernel/system libraries are prerequisites.

The collector inspects only actual ELF library files while keeping executable
inspection strict; LLVM linker scripts are not treated as shared objects.

Shared `just check` now includes the bounded coverage report; CI retains it and
installable archives and tests the extracted package before upload. Version tags
run the same checks, then publish assets only after both platforms pass. Root
README and CODEOWNERS now cover installation and the trusted launcher/packager;
the technical lead authorized these additions. No logical baseline was changed.
The complete integrated `nix develop --command just check` passes: build, pinned
engine/grammar, native/model, kernel gate, isolated compiler, all 16 CLI cases,
five coverage regressions, 11 discovered regressions, and refreshed coverage report.

## Current cross-platform checkpoint

Reviewed fix `522b2b57` shares one runtime selection between inspection and
copying: direct `lib` files and the complete `lib/lean` tree, excluding compiler
SDKs. Absolute dependencies outside the copied set still reject. Hosted macOS
run `35995826585` passes full source checks, archive building and installed smoke.
Lead and independent conformance review also installed the narrowed archive:
`3f89e1c416a1781423c9565de78ba508189409c8a53ec4b7d63be572b89c562e`.

Linux run `35997069355` identifies the remaining checker startup cause: the
collector retained a library symlink's resolved Nix package but dropped the
referenced package path. Both loader-cache probes fail identically; adding the
cache is not a fix. Change `5ab817ec` retains both exact package roots, with no
broader runtime permissions. Independent conformance review reproduces all three
focused tests. The temporary cache probe is removed; labeled loader artifacts
remain. See [loader evidence](20260924-linux-loader.status.md) for exact paths.
The lead authorized integration; root's three focused tests pass (0.078 seconds),
and Actionlint/ShellCheck pass on the integrated workflow.
Full hosted Linux package confirmation now passes in run `35998140680`, as does
macOS. The source, coverage, loader and runtime artifacts are retained.

The lead's final requirements audit found no additional engineering gap beyond
cross-platform package evidence and prerelease publication. The stale task header
now reflects implementation progress. The authorized engineering preview is
`v0.1.0-rc.1`; it was tagged on 2026-09-25 after both main jobs passed and started
[release run 36102477873](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36102477873).
Stable release and Step 1 DONE still require the actual pilot and owner acceptance.
