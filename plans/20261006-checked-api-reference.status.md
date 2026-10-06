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

## Acceptance remaining

Dependency closure and sandboxed reference build; complete checked public
documentation and proposition restatements; compiling walkthrough; negative
Verso fixtures; README and CLI help links; CI output and both platform checks;
independent reviews. The upgraded runtime's final owner review remains open.
