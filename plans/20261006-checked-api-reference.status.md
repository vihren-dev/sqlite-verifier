# Checked API documentation and reference status

Status: IN PROGRESS. Created 2026-10-06.

Task: [checked API reference](20261006-checked-api-reference.task.md).
Source: [issue #26](https://github.com/vihren-dev/sqlite-verifier/issues/26).
Rules: [AGENTS.md](../AGENTS.md).

Relevant sources: `SqliteVerifier.lean`, `SqliteVerifier/*.lean`,
`lakefile.toml`, `build-support/default.nix`, `build-support/sources.nix`,
`.github/workflows/ci.yml`, `README.md` and CLI argument definitions.

## Progress

- 2026-10-06: Reused the idle maintenance Jujutsu workspace. Its base merges
  the checked Lean upgrade `6917e3c8` with merged main `e9fd9533`, which supplies
  the documentation rules and catalog correction. Preserved every original
  raw review entry from main, the upgrade and the maintenance integration.
- 2026-10-06: Verified the upstream doc-gen4 `v4.34.1` tag directly through
  GitHub's Git-reference API. It resolves to
  `953c8992d174b4e56955e01e101d46668c68f2bb`; an exact matching tag is available.
  The older `v4.34.0` manifest confirms that doc-gen4 has separately pinned
  Lake dependencies and a native SQLite binding. The matching tag's actual
  manifest and native build inputs must be inspected before implementation.
- 2026-10-06: Identified 188 top-level declarations in the current public
  library modules, before counting fields and constructors. Prepared the
  observable task and negative documentation checks before code changes.
  No reference implementation or public docstring change has started.
- 2026-10-06: Added separate `docGen4` and `apiReference` Nix targets. The
  generator uses all five exact dependencies from its v4.34.1 manifest,
  including bundled SQLite, Markdown and Unicode native code. Each original
  manifest pin is checked before its fixed require clause and manifest entry
  become local Lake paths. All six real manifests passed this conversion;
  the generator built in a native Darwin Nix sandbox and its installed
  executable passed its help check. The production Lake manifest is unchanged.
- 2026-10-06: Added `just reference FULL_COMMIT_HASH`, explicit public source
  URIs, reference output validation and both-platform CI artifact retention.
  Generation calls the pinned CLI directly, without Git source facets. The
  public library source links identify the unchanged checked baseline
  `edf68e1cf917a99b257c01bcc659a4f89b4ed68d`; complete public documentation is a
  separate part of this task and needs final combined-source generation.
- 2026-10-06: The first real run exposed a validator path mistake: doc-gen4
  stores full per-module metadata in internal `doc-data`, rather than final
  `doc/declarations`. The second run exposed HTML fragment handling and
  genuine upstream links to omitted recursors. Corrected the metadata path
  and HTML-standard top/named/raw/decoded fragments. Reference generation
  redirects only missing known recursor links to existing parent-type anchors
  and corrects the pinned core `Init/Tactic.html` typo to `Init/Tactics.html`.
  Arbitrary missing pages and anchors still fail.
- 2026-10-06: Preserved the retained Nix output after host diagnostics met
  the build user's intentional ownership. With parent feedback, copied and
  SHA-256 verified all 3,518 diagnostic files into ignored workspace `build/`.
  The writable copy passed validation after 178 corrections. The correction
  runs before install inside the Nix builder, which owns its generated files.
- 2026-10-06: A native sandbox reference run passed with 20 public modules,
  334 generator-rendered declarations, 1,166 HTML pages, 829,625 local links and 178 corrected
  links. Its build phase took 4 minutes 40 seconds. Upstream documentation
  generation warned that four Std.Time equational-lemma computations reached
  their heartbeat limit; generation and all output checks passed. This is
  baseline documentation, rather than evidence of completed Verso coverage.
- 2026-10-06: Focused checks pass 25 tests and 28 subtests, including exact
  manifest refusal, missing output/source identities, valid HTML fragments,
  known link correction and preservation of an existing raw fragment ID.
  Authored Markdown links pass. The 53-path proof runtime closure excludes
  doc-gen4 and its documentation packages. The last raw-fragment guard is
  checked in a final native sandbox run: exit 0, build phase 4 minutes 35
  seconds, output
  `/nix/store/kr5zl3jbnr2cslppsw5yh4rdf1b0x3ng-sqlite-verifier-api-reference-edf68e1cf917`.
  That output has the same checked counts and includes the final guard. The
  334 rendered declarations include compiler-generated declarations; they
  are not an authored Verso coverage count. This packaging checkpoint awaits
  its independent commit review.
- 2026-10-06: Packaging commit `70afca59` received no must findings and four
  should findings. Fixed all four: one documented commit-hash pattern shared
  by both Python tools, a named generator package policy, received-value and
  argument context in the revision diagnostic, and negative duplicate,
  branch-shaped revision and changed dependency-set checks. The shared policy
  is a four-line Python module included through a narrow Nix Python path.
  Recorded each finding as fixed through `just review-resolve`.
- 2026-10-06: These fixes pass 29 focused tests and 28 subtests, and the complete
  native generator/reference sandbox build. Its final output is
  `/nix/store/0dm44vw3ny9zp5kbvnlvkyiiv0j6c2jf-sqlite-verifier-api-reference-edf68e1cf917`,
  with the same 20 modules, 334 rendered declarations, 1,166 pages, 829,625
  local links and 178 corrections. The reference build phase took 4 minutes
  41 seconds. Both sandbox scripts imported the shared policy successfully.
  The reference tool stays below 200 lines. The checked refactor now awaits
  its required independent review.
- 2026-10-06: Refactor `5eddcc97` received no must findings and one should:
  link the Nix revision guard to the shared Python hash policy. Named the Nix
  pattern and added a cross-language consistency test. All 30 focused tests
  and 28 subtests pass. `just reference` reuses the same successful Nix output;
  naming the guard did not change its derivation. Recorded the finding fixed
  through the review tool. The final correction awaits independent review.
- 2026-10-06: Final correction `79a0a960` passed independent Claude review
  with no findings. All findings from this packaging sequence are fixed.
  The final review entry remains in the append-only working-copy journal for
  the next integration commit. Packaging, reference generation, link checks,
  source-policy checks, documentation and the CI hook are ready to merge with
  the authored-documentation changes. Final combined checks must include the
  reviewed storage/main fixture correction (`e757275e`, `28c3e082`) before
  running complete Nix identity checks; its source fixture includes `tools/`.
- 2026-10-06: The matching `v4.34.1` manifest has the same five dependency
  revisions as `v4.34.0`, and its toolchain file selects Lean 4.34.1. Fetched
  and hashed all six exact public sources; local receipts are in
  `build/docgen-source-pins.json`. MD4Lean, UnicodeBasic and leansqlite compile
  bundled native C sources. No SQLite execution-profile version changes.
- 2026-10-06: The combined baseline passes the ordinary command
  `nix develop path:./nix --command timeout 1200 just test`: 328 source tests
  and 28 subtests, plus all six development Nix targets. The complete log is
  `build/t18b-base-integration-check.log`. No executable or formula was changed
  by this baseline merge. Packaging will use doc-gen4's explicit `single` and
  `fromDb` interface, which can avoid its Git-dependent source-URI facets.
- 2026-10-06: The baseline merge passed Claude review with no findings
  (`20261006T142821Z-edf68e1c`). The reference build uses an isolated Jujutsu
  workspace; this workspace owns public declaration documentation.
- 2026-10-06: Added checked Verso documentation to every authored declaration,
  constructor and field in `SqliteVerifier/Declarations.lean`, with exact
  descriptions of type-spelling compatibility and the plain-column predicate.
  Checked examples retain the field defaults and BIGINT spelling. The module
  compiles without documentation warnings and remains below 200 lines.
- 2026-10-06: Four real compiler tests pass in 2.18 seconds: a true checked
  example is accepted, while an unknown reference, ill-typed example and false
  assertion each fail at their actual source location. Sandboxed `leanRuntime`
  compilation also passes for the complete public library, existing proof
  examples and both gates. Log: `build/t18b-declarations-check.log`; JUnit:
  `build/test-results/checked-docs.xml`. No formula or definition body changed.
- 2026-10-06: Documentation review `20261006T145114Z-e9f07fe9` had no must
  findings and two should findings. Restored the reasons for retaining type
  spelling (the INTEGER/BIGINT rowid distinction) and requiring plain created
  or added columns. Both findings are recorded as fixed through the review
  command. The corrected module compiles without warnings; this correction
  changes no term, formula or checked example.
- 2026-10-06: Correction `d01db1e6` passed Claude review with no findings
  (`20261006T151029Z-d01db1e6`). Its related observation about a model
  restriction reported as a failure belongs to the planned validity/domain
  separation; this documentation unit does not change those formulas.
- 2026-10-06: Added checked documentation to every authored declaration,
  constructor and field in `SqliteVerifier/Model.lean`. Proposition statements
  now state each conjunct and quantify stored rows, schema entries and table
  lookups, including their empty/absent cases. Lookup and projection docs
  describe the first match and missing-cell behavior exactly. The model module
  is 199 lines and compiles without documentation warnings.
- 2026-10-06: Complete sandboxed `leanRuntime` compilation passes against the
  checked model documentation, including existing public proofs and both
  gates. Log: `build/t18b-model-check.log`; output:
  `/nix/store/70bscijcagr3s02fcphyjcf5rj0lahy9-sqlite-verifier-lean-runtime-1`.
  No formula or definition body changed.

- 2026-10-06: Model documentation review `20261006T155010Z-19d3b2c7`
  reports no must findings and five should findings. Restored the reasons for
  the fixed SQLite column limit, typeless statistics columns, ASCII identifier
  folding, ordered schemas and the executable empty database. The final
  empty-database statement requires `Conforms`, which includes schema and
  table validity. Recorded all five findings as fixed. The corrected module
  remains 199 lines and compiles without documentation warnings; no formula
  or definition body changed.

- 2026-10-06: Model correction `12bd6ade` passes independent review with no
  findings (`20261006T160157Z-12bd6ade`). All five earlier should findings have
  fixed resolution records in the append-only journal.
- 2026-10-06: Added checked documentation to every authored declaration and
  field in `SchemaExtension.lean` and `NullableProjection.lean`. Their reusable
  theorem statements now quantify all inputs, state every assumption, describe
  absent/empty cases and give proof sketches. The nullable view distinguishes
  an unrequested field from an observed empty projection. Both modules and
  their checked examples compile without warnings in the pinned Lean runtime;
  they contain 77 and 63 lines. Formulae and definition bodies are unchanged.

- 2026-10-06: Schema-update and nullable-observation documentation `78cd697b`
  passes Claude review with no findings (`20261006T160355Z-78cd697b`).
- 2026-10-06: Added checked documentation to every authored declaration in
  `LiteralData.lean` and `LiteralPreservation.lean`. The readiness predicates
  describe their exact affinity and value domains, and distinguish admission
  from the new table's constraints. The constraint docs expose zipped-cell
  checks and their separate width requirement. All reusable theorem statements
  include assumptions, quantified inputs, empty cases and proof sketches.
  Both modules and their computed examples compile without warnings in the
  pinned runtime; they contain 144 and 165 lines. Formulae and definition
  bodies remain unchanged.

- 2026-10-06: Literal documentation review `20261006T160656Z-f969698a`
  reports no must findings and one should finding. Replaced the ambiguous
  phrase "empty rows" with "a table with no rows" in the constraint docstring;
  rows with no cells are not the intended empty case. The corrected module
  compiles without warnings and remains 144 lines. No formula changed.

- 2026-10-06: Literal correction `116c03e2` passes Claude review with no
  findings (`20261006T160803Z-116c03e2`). The ambiguous empty case is resolved.
- 2026-10-06: Added checked documentation to every authored declaration in
  `Library.lean`. Coverage, representation soundness and update/preservation
  statements now describe exact assumptions, quantified inputs and empty
  cases. Reusable theorems have short proof sketches; the false failure
  invariant's vacuous soundness is explicit. The module compiles without
  warnings in the pinned runtime and contains 187 lines. No formula or
  definition body changed. T05 owns a separate import change to its extracted
  ContractProofs module; this documentation unit does not change that import.

- 2026-10-06: Library documentation `fab39cc7` passes independent review
  with no findings (`20261006T161029Z-fab39cc7`). Its real local compiler check
  passed before commit; the reviewer did not independently rerun compilation.
- 2026-10-06: Added checked documentation to all authored declarations and
  concrete proof examples in `SchemaPreservation.lean` and `SchemaExamples.lean`.
  The key meaning remains an arbitrary user-supplied predicate. The column
  invariant explicitly requires coverage of the supplied column's name, not
  equality between the supplied metadata and a stored declaration. All theorem
  statements include actual assumptions, quantified inputs, empty cases and
  short proof sketches. Both modules and their computed examples compile;
  the retained schema guards pass. They contain 76 and 70 lines. No formula
  or definition body changed.

- 2026-10-06: Schema documentation review `20261006T161513Z-edbd2d57`
  reports no must findings and one should finding. The properties example now
  gives a checked constructor for an empty properties value, rather than an
  unrelated assertion about the example's UNIQUE constraints. Recorded the
  finding as fixed. The corrected example module compiles without warnings;
  no formula, definition body or existing schema guard changed.

- 2026-10-06: Schema example correction `34c35b16` passes independent review
  with no findings (`20261006T161714Z-34c35b16`). Nine public-library modules
  now have compiled, independently reviewed checked documentation: Declarations,
  Model, Library, SchemaExtension, NullableProjection, LiteralData,
  LiteralPreservation, SchemaPreservation and SchemaExamples. Every earlier
  should finding in these units has a fixed outcome in the review journal.
  The final raw review entry remains pending for the next integration commit.
  T05 owns the remaining changed execution/contract/example modules and their
  documentation. The reference branch owns packaging and authored coverage.
  Full authored coverage, the walkthrough and combined acceptance remain open.

- 2026-10-06: The authoritative inventory on exact reviewed T05 source
  `0eb80129` and runtime `15n2iy9b` finds 259 authored public declarations,
  constructors and fields across 21 imported modules. All 259 have checked
  Verso documentation; no ordinary, missing or unclassified declaration remains.
  Compiler/parser evidence accounts for 941 generated/private/transient
  exclusions. This receipt precedes T15's two new public modules and is not
  final coverage for the enlarged library.
- 2026-10-06: Added the checked public-entry walkthrough: empty-data admission
  witness, plain-column defaults, rowid versus application-key observations,
  general contract primitives, complete verification obligations and a complete
  demonstration certificate. Its three Lean code blocks compile against the
  actual assembled runtime. Five real compiler tests also pass on that runtime,
  including all four positive/negative documentation cases. The walkthrough
  still needs final combined reference/runtime and coverage acceptance.

- 2026-10-06: Added compiler-derived authored coverage from the actual imported
  environment. Original `.ilean` constant binders join exact parser selections;
  grouped fields, explicit constructors and anonymous instances remain visible.
  Direct Verso metadata supplies checked status. Compiler-private declarations,
  anonymous examples, generated recursors, implicit constructors and deriving
  helpers retain explicit exclusion evidence. Unknown authored syntax fails
  closed. The imported module closure is dynamic and source/reference hashes
  accompany exact names and UTF-16 positions.
- 2026-10-06: Eight real compiler fixture checks pass with short subprocess
  deadlines. They distinguish 13 authored items from generated helpers, discover
  a new imported module, detect five missing/ordinary/inherited-only documentation
  variants, and refuse an unclassified original binder from custom syntax.
  The baseline diagnostic identifies 270 authored items: 188 ordinary, 82 missing,
  zero checked and zero unclassified, with 941 explicit exclusions. This report
  describes the unchanged baseline, not the parallel merged documentation work.
- 2026-10-06: Added separate lazy `publicDocumentation`, development/test-full
  recipe prerequisites and strict reference-build coverage with retained JSON.
  All seven existing Nix test targets still evaluate without the reference or
  coverage target. A native sandbox run of the separate coverage target correctly
  refuses the cached incomplete baseline with the same counts and exact source
  diagnostics. Focused reference/dependency/coverage checks pass, and authored
  Markdown links resolve. This checkpoint awaits independent commit review.
- 2026-10-06: Inventory checkpoint `9f6f8bed` received zero must and three
  should findings. Named the exact private/generated/example exclusion policies,
  documented all parser roles, and added module/declaration context to invalid
  selection diagnostics with a focused negative check. The strict baseline
  refusal remains expected until the parallel checked documentation is merged.
- 2026-10-06: Refactor `8ba9f205` passed independent Claude review with no
  findings. Its final raw review entry stays in the journal. Exact reviewed T05
  source `0eb80129d784693a3aaf773b0bfa4c66699bbcd6`, paired with its complete
  compiled runtime, has 259 authored items across 21 actual imported modules;
  all 259 have checked Verso documentation, with zero ordinary or missing docs.
  A fail-closed temporary module-example classification exposed the need for
  compiled checked-documentation source-range evidence. Added module Verso
  ranges and parser comment ranges confirmed by direct declaration Verso
  metadata. Temporary documentation declarations now have explicit exclusion
  evidence, and that exact T05 source passes with zero unclassified items and
  941 exclusions. The final merged T15 modules are not yet part of this report.
- 2026-10-06: All 31 focused checks pass after this classification correction,
  including nine real compiler cases and an invalid-selection diagnostic check.
  The complete fixture has 14 authored checked items. Separate declaration and
  module examples demonstrate temporary-command exclusions by compiler-confirmed
  comment ranges. Every changed source file remains below 200 lines. This
  checked-documentation correction awaits independent commit review.
- 2026-10-06: Checked-documentation commit `e7655ade` received zero must and
  two should findings about malformed-array diagnostic context. Both array
  errors now identify the module, and declaration arrays also identify the
  declaration. Two focused malformed-metadata checks verify these caller paths.
  All 33 focused checks pass. This diagnostic refactor awaits independent review.
- 2026-10-06: Final diagnostic refactor `63bcc787` passed independent Claude
  review with no findings. All inventory findings are fixed. The final raw
  review row remains in the append-only working-copy journal for integration.
  Compiler inventory, fixtures and the separate strict Nix/recipe/reference
  gate are ready to merge. Exact T05 coverage is complete, but final acceptance
  must use the newly assembled application-key modules and walkthrough with
  their exact compiled artifact, then both-platform reference checks. The
  earlier runtime without walkthrough metadata cannot establish final coverage.
- 2026-10-06: Assembled reviewed `cd62cda7` and `f7f5ccb3`. All 119 raw
  journal rows remain unchanged, with both original journals verified as exact
  ordered subsequences. Kept the reviewed unpatched exporter source interface
  and adapted reference source copying to it. The exact merged runtime built
  successfully as `/nix/store/f8a2l6amcpjlvss4r6hcs1sz97mn22h5-sqlite-verifier-runtime-1`.
  The native strict inventory target passes across 23 actual public modules:
  273 authored, all 273 checked, zero ordinary, missing or unclassified, with
  947 explicit exclusions. Both application-key modules have 7 checked authored
  items, and the walkthrough's compiled Verso range is present. Every recorded
  source SHA-256 matches the current source file. The report is retained under
  `/nix/store/zmxhgskmp4rjgwsg009kb8gf6zx1yipn-sqlite-verifier-public-documentation-1`.
  All 38 focused compiler/reference/dependency cases and both-platform lazy
  Nix test-projection checks pass. Reference evaluation succeeds. This assembly
  awaits independent review and exact-commit native reference generation.
- 2026-10-06: Assembly `6b47be64` passed independent Claude review with no
  findings. Its exact-commit native Darwin sandbox reference build passed in
  4 minutes 31 seconds. The output is
  `/nix/store/c43n80xbvia86i7ckywvfd5899d4bm6y-sqlite-verifier-api-reference-6b47be648021`.
  It contains 23 public modules, 337 generator-rendered declarations, 1,169 HTML
  pages, 829,820 validated local links and 178 corrected upstream links. Its
  source identity is `6b47be648021d46fb212d9001cd35576f180c45b`.
  The separately retained authored inventory confirms all 273 authored items
  have checked Verso documentation, with zero ordinary, missing or unclassified
  items and 947 explicit exclusions. The four known upstream Std.Time heartbeat
  warnings remain in the build log; all generation and validation gates passed.
  The fresh proof runtime has 53 requisite paths and excludes the generator
  and its documentation dependencies. The final raw assembly review row remains
  in the working-copy journal for the next integration commit. The Darwin heavy
  build slot is released.
- 2026-10-06: Merged reviewed schema-binding phase `1432aec5` by named
  revision, preserving all 121 original raw journal rows and both ordered
  journal subsequences, including its pending review and the `6b47be64` review.
  Added README links to the API guide and CLI input roles. CLI input help
  explains approved requirements/admission/current meaning, candidate SQL and
  resulting/failure meanings, and proof or refutation roles. Command help states
  the universal starting-data scope and interpretation soundness obligations.
  Standard raw-description formatting keeps the guide URL intact. Commands,
  required paths, defaults and verification statuses are unchanged. Nine focused
  CLI/default/Markdown checks pass. This prose checkpoint awaits independent
  review. The immutable `6b47be64` reference remains the earlier 23-module record;
  the separately reviewed demonstration module needs fresh combined coverage.
- 2026-10-06: Prose `f8f42bbf` passed independent review with no findings.
  Merged it with reviewed `731f03c8`, preserving all 130 original raw journal
  rows and both ordered source journals. Fresh runtime
  `/nix/store/v13z7m885d3bnqbn06lw2fv7b12wjnq6-sqlite-verifier-runtime-1`
  compiles the expanded public entry and prints the guide/input roles from its
  real CLI entrypoint. The strict native inventory target passes for 24 actual
  modules: 281 authored, all 281 checked, zero ordinary, missing or unclassified,
  with 964 exclusions. The new demonstration contributes eight authored checked
  declarations. Every recorded source hash matches the current public file.
  All 47 focused compiler, help/default, reference/dependency and Markdown cases
  pass. This expanded assembly awaits independent review and exact-source
  reference generation. The Linux lease is released; the separate fresh task
  directory is `/var/tmp/sqlite-verifier-reference.zgvSyF` on native x86_64 Linux.
- 2026-10-06: Final source assembly `dac12b49` passed independent review with
  no findings. Its 130 committed raw journal rows parse as JSON and remain
  unique. Native Darwin and native x86_64 Linux reference builds both passed
  from exactly that public tracked revision. Their receipts agree: 24 modules,
  345 rendered declarations, 1,170 HTML pages, 829,888 validated local links and
  178 corrected upstream links. Both retain complete authored coverage:
  281 authored and checked, zero ordinary, missing or unclassified, with 964
  explicit exclusions. Build phases took 5 minutes 6 seconds on Darwin and
  6 minutes 58 seconds on Linux. The four known upstream Std.Time heartbeat
  warnings remain; both generation and validation passed.
  Linux transfer verified all 896 tracked entries, including the documentation
  symlink, and 895 regular source hashes before and after execution. Retained
  exact helper/archive hashes and native result-file hashes were independently
  verified from the original compressed receipts. The public receipt is
  [native acceptance](../reports/20261006-checked-api-reference/native-acceptance.json).
  The earlier `6b47be64` artifact remains immutable with a separate Nix root.
  Both heavy leases are released. The final `dac12b49` raw review row remains
  in the working-copy journal for the next authorized integration. Further
  implementation is held during the owner's review.
- 2026-10-06: Native receipt/status checkpoint `72c98d57` passed independent
  Claude review with no findings. The final source and receipt reviews remain
  raw in the working-copy journal for the next authorized integration. All
  implementation and native acceptance work is complete; only the explicitly
  recorded hosted CI build/artifact acceptance remains. No further T18b work
  starts during the review hold.

- 2026-10-06: Status is HELD after complete native acceptance. The owner review
  freeze permits only this status checkpoint. Both pending raw review rows
  remain unchanged for the next authorized integration; hosted artifact
  acceptance must wait for publication authorization.

## Acceptance remaining

The owner approved PRs #43, #44, #47 and #48, and T03's release is complete.
At audit checkpoint `176196be`, the original review freeze had ended. The
mixed branch remained HELD for clean dependency integration and hosted
artifact acceptance.

On 2026-10-07, a read-only comparison against approved executor `8e10a593`
found that the current branch also contains T15's three ApplicationKey modules,
example checks and public imports. The 92-path raw difference would also
remove accepted ADR and receipt files and revert the mutation extraction and
model timeout correction. It must not be published as a T18b-only difference.
The native reference receipts remain exact evidence for their original mixed
source `dac12b49`; they do not establish acceptance of a clean change on the
delivered base. Preserve that history, isolate only T18b's reference, inventory,
walkthrough and help changes, then run the required current-source acceptance.
No source change, build or new acceptance occurred in this audit.

Hosted CI must build and retain both platform artifacts from the published
reviewed source. This has not run in this task. The original mixed-source
implementation passed its link, coverage, compiler, native reference and review
checks. Those results do not establish clean-source acceptance. The upgraded
runtime and T05 trust changes retain their separate owner-review records.

## Clean isolation resumed on 2026-10-07

The four requested owner reviews are complete. Preserve the mixed workspace at
local bookmark `t18b-mixed-history-acceptance` (`6dce0468`). Isolate only T18b
tooling, CLI help, walkthrough and build integration over reviewed executor
head `9e91e525`, which includes main `aeffab25` and the checked Darwin schedule.
The executor still awaits hosted acceptance and delivery. T15 modules and
examples are excluded. Existing model budgets, mutation checks, baseline
bindings, scheduling, accepted ADR and historical receipts must remain intact.
The standalone walkthrough uses only this base's public declarations.

Source and bounded tooling checks can proceed while T15 holds the Darwin
native lease. Fresh native reference builds wait for that lease. Prior mixed
builds remain historical evidence. No new PR, reference output or hosted pass
is claimed by this planning checkpoint.

The first isolated tooling run passed 44 tests and 28 subtests in 3.69 seconds,
but the Markdown gate failed because the restored status linked to a missing
historical receipt. Restored that exact receipt from `6dce0468`; no raw evidence
was changed. The original XML remains `build/t18b-clean-source-isolation/tooling.xml`.
Actual rendered Nix commands pass their ownership check in 1.54 seconds,
retaining all seven targets and the existing 420/600-second budgets.
The 161 base journal rows and 132 mixed-source rows combine into 198 rows,
preserving both orders and repeated entries. All 73 approved source, pin and
baseline files outside the entry-point walkthrough remain unchanged; that
entry point keeps its imports and formulas. No T15 module or example is copied.
The corrected local Markdown gate passes both tests in 0.66 seconds.
Compiler fixtures and the adapted walkthrough still await their coordinated
check. No reference build or clean-source completion is claimed.

The adapted public walkthrough compiles with exit zero under a 30-second
bound. It imports only the approved base modules. Sixteen real compiler
fixtures pass in 57.47 seconds under 120 seconds, including source-location
failures, authored fields, generated exclusions and checked module comments.
They use the fresh T15 runtime's pinned compiler and unchanged dependency
modules; they do not validate the T15 public entry or replace a clean Nix build.
The walkthrough artifacts and original fixture XML are retained in
`build/t18b-clean-source-isolation/`. No source compiler or test failure remains
in this isolated unit. Ordinary integration, both fresh native references,
hosted artifact retention and final delivery still remain.

Independent review of `db01381d` returned zero must findings and one R11
suggestion (`20261007T093912Z-db01381d#1`). The `--report-only` success override
had no caller or required use. Removed it; incomplete coverage now always
fails the CLI gate after writing the complete report. The inventory function
still supplies diagnostic data to callers. Recorded the suggestion as fixed.
All five actual incomplete-coverage fixtures and both link checks pass in
22.50 seconds under 120 seconds. This correction changes no compiler helper,
coverage classification, proof rule or reference layout.

## Clean native acceptance on 2026-10-07

Correction `2df58fd1` passed independent Claude review with no findings
(`20261007T094526Z-2df58fd1`). Its exact source then passed fresh native
reference builds on Darwin and Linux. Both outputs contain 21 public modules,
323 rendered declarations, 1,167 HTML pages, 829,618 valid local links and 178
corrected upstream links. The actual compiler inventory has 259 authored
declarations, all checked, with zero documentation gaps and 942 explicit
exclusions. These counts exclude T15 and T07. All module source digests and
output dependency pins match the reviewed source.

Darwin's first attempt stalled. The owner authorized cancellation of the
verified process group; its terminal exit was 137. An ambient retry exited 127
because `timeout` was unavailable, before Nix started. The authorized retry
used the pinned Nix shell and unchanged 1,800-second build deadline, with a
10-second forced cleanup guard. Its actual terminal exit was zero. Its console
records a 5-minute 5-second reference build phase. No retry UTC or monotonic
boundaries were captured; the source snapshots cover all attempts and are not
a retry duration. All 968 captured tracked entries, including the documentation
symlink, match before and after. The pending review journal was explicitly
excluded from those snapshots.

Linux used a fresh isolated directory and an exact public tracked archive.
The output was invalid before the single build. The complete recipe exited
zero after 418.351160823 seconds, within its 1,800-second bound; its console
records a 6-minute 56-second build phase. All 969 tracked entries, including
968 regular files, their executable bits and the documentation symlink, match
before and after. Archive and capture helper hashes are unchanged. The native
receipts retain the exact commands, resource guard, sandbox policy, source and
output identities. A local audit first assumed an older Nix JSON layout; the
corrected audit checked the host's actual version-4 derivation format. No build
was repeated for that audit correction.

Both generators emitted the same four previously recorded upstream Std.Time
heartbeat warnings. Generation and complete link validation passed. The
[clean native acceptance record](../reports/20261007-checked-api-reference-native/README.md)
retains all original logs and metadata, including the failed Darwin attempts.
The historical mixed-source receipt remains unchanged. Both native heavy slots
are released. This evidence checkpoint changes no feature source or baseline.

Status remains IN PROGRESS. Relevant ordinary source/development and Nix
infrastructure checks still need the reviewed deadline/base integration.
Both hosted native reference artifacts must then build and be retained from
the published reviewed source, followed by normal PR delivery. This checkpoint
does not claim those remaining checks or task completion.

The evidence checks verify both archive hashes and all 40 original payload
hashes against the retained files, matching native metadata, successful exit
records, exact pins and the unchanged historical receipt. Both Markdown tests
pass in 0.49 seconds under a 60-second bound. The pending clean `2df58fd1`
review row is preserved exactly. The evidence unit now awaits independent
review; no ordinary native check starts before that review is clean.

Evidence `1090de7b` passed independent Claude review with no findings
(`20261007T113845Z-1090de7b`). The reviewer could inspect the metadata but could
not run archive tools under its command allowlist. The implementer's separate
checks verified every archive and original payload against the retained files.
Clarified spaces around status codes and the executor revision in the derived
JSON summary. All original logs, metadata payloads and archive bytes remain
unchanged. This wording correction awaits review. No heavy check has started.

Correction `7fd10159` passed independent Claude review with no findings
(`20261007T113950Z-7fd10159`). Native evidence is ready. The next integration
must use the reviewed complete-job deadline correction coordinated by the
parent. The proposed whole-job budget is 105 minutes: the base's 75 minutes
plus the existing 1,800-second reference phase outside the orchestrator. A
guard must account for that actual workflow phase and preserve all child
limits, including 600 seconds for model and 420 for the other Nix suites.
No deadline or implementation change is made in this readiness record.

After that integration, required local checks are the ordinary `just test`
recipe (source checks, public inventory and all six development Nix targets),
`just test-nix`, and the proof runtime's exclusion of documentation packages.
Native leases must be coordinated before these checks. Full model, performance
and acquisition work are excluded from this local acceptance unit. Hosted
checks must still exercise the complete existing recipes and retain both
reference artifacts from the published reviewed head. Publication and normal
delivery remain with the parent. The final raw review row remains pending for
the next integration; Status remains IN PROGRESS.


## Integration with delivered main

Accepted main is now `923b7cee`, including T13 and the 75-minute CI repair.
The unpublished T18b branch is being integrated with that base. Only the
review journal conflicts. The 208-row feature journal, 252-row main journal
and 209-row pending journal remain ordered subsequences of the 294-row
result; repeated rows are preserved. Main source, evidence and baselines
are retained.

The reference step currently follows the runtime platform guard, which
skips macOS on PRs. The task requires both hosted reference artifacts.
Reference setup, generation and retention will run on both native platforms
for non-documentation scopes; runtime checks keep their existing guard.
The combined job budget is 105 minutes, accounting for the existing
1,800-second reference phase in addition to the accepted native budget.
No child timeout or dependency pin changes. Local expensive checks remain
on hold at the resource guard while cleanup approval is pending. Bounded
workflow checks and Linux acceptance can proceed.


The integrated workflow passes 54 bounded checks and 35 subtests in
1.21 seconds under a 120-second limit. Twelve native or Nix checks are
explicitly deselected. Reference Lean sources, tooling and pins have no
changed file against accepted native source `2df58fd1`; no new native
reference execution is claimed. [The integration record](../reports/20261007-checked-api-reference-main-integration/README.md)
retains the original XML and journal proof. The current source preserves
delivered main and its checks. Independent review remains required before
draft publication for hosted acceptance.


Integration `ba3f3213` passes independent review
`20261007T175523Z-ba3f3213` with no mandatory finding. Two stale
descriptions are corrected: the old hosted budget and the old statement
that PRs run only on Linux. The reference runs on both platforms while
verifier checks retain their schedule. No workflow behavior changes in
this text correction. Both findings are recorded as fixed; correction
review remains required.


Correction `88ea1c48` passes independent review
`20261007T175732Z-88ea1c48` with no findings. The two previous
descriptions have fixed journal resolutions. Draft publication will use
the new clean branch against delivered main `923b7cee`. Its reference
job runs on both platforms; verifier checks retain the Linux PR schedule.
The current development set has seven Nix suites. The earlier six-suite
readiness wording is historical. Original native reference receipts are
retained, and no new local expensive acceptance is claimed. Hosted
reference artifacts, ordinary checks and normal delivery remain required.


Draft [PR57](https://github.com/vihren-dev/sqlite-verifier/pull/57) is
published at `773827a1`. CI `37663864057` is live and generating the
reference on both native platforms. Read-only metadata checks verify
that both runtime derivation graphs exclude the generator and reference
output. The existing exact macOS runtime output is valid, and its
53-path output closure contains no generator or reference artifact. No
local runtime build or garbage collection runs. Actual Linux output
closure and ordinary local acceptance remain required. This evidence
checkpoint does not move the published branch while CI is live.


CI `37663864057` builds both native references successfully. The Linux
source step then fails nine real inventory checks: `findSysroot` invokes
ambient `lean`, which exits 255, although the explicit runtime compiler
is valid. This is an invocation bug, not reference acceptance or a
missing compiler. Original Linux source results report nine failures,
399 passes, two optional reviewer-tool skips and 35 subtests.

The inventory wrapper now queries the chosen compiler for its prefix
and supplies that sysroot to both helper calls. The existing positive
compiler fixture places a failing `lean` first on PATH. It must still
produce the complete actual inventory. Full affected compiler fixtures
remain required before commit; the failed hosted run is retained.


The compiler sysroot fix passes all 12 affected checks in 39.61 seconds
under a 120-second limit. The strengthened positive fixture clears any
inherited sysroot and puts a failing `lean` first on PATH; it passes in
3.63 seconds under a 90-second limit. [The correction record](../reports/20261007-reference-compiler-sysroot/README.md)
retains the original Linux failure, both hosted reference receipts and
the new local XML. Both hosted reference ZIP hashes match their artifact
digests. Corrected hosted source acceptance remains required. No Nix
or runtime build ran locally. Independent review is pending.
