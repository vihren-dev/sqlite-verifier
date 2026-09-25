# Step 1 status

Created: 2026-09-24. Status: OWNER ACCEPTED — final release validation pending.
Task: [Verified SQLite schema extensions](20260924-step-1-schema-extensions.task.md).
Final release: [task and evidence](20260925-step1-release.status.md).

## Owner acceptance and current scope

On 2026-09-25 the product owner approved the current Atuin example and then
explicitly approved the current product state and requested completion of Step 1.
The authoritative contract is engineering brief revision 0.7: SQL files are the
universal input; the primary guarantee is preservation of the approved old
business model while its representation changes. The new interpretation reads
that old model from resulting storage. No anticipated shell field, SQLx catalog
correctness, ORM integration, live execution or runner certification is required.

Implementation 0c5bb79e passed the full local `just check`. Its Atuin proof verifies
the upstream one-statement ALTER payload for arbitrary admitted initial data.
The same six approved Lean modules and schema hash also verify a differently
named nullable added column with revised candidate proofs. Eleven rejection
cases cover protected-input changes, unsupported semantics, dropped histories,
erased commands, weakened representation and unfinished/stale proofs.

Human evidence is the owner's iterative definition, review and acceptance of the
business model and preservation contract. Agents authored proofs, executed checks
and repaired rejected proposals. No reliable human timing or previous-workflow
benchmark was collected; no quantified productivity improvement is claimed. The
owner's final acceptance closes this qualitative pilot review. See the
[pilot record](../docs/atuin-pilot-review.md).

## Delivered engineering

- Public SQL/Lean CLI, JSON and human diagnostics; exact input/profile binding.
- Pinned complete SQLite grammars for 3.51.0 and 3.46.0, distinct from the bounded
  semantic subset; source spans and fail-closed unsupported behavior.
- General logical contracts, separate before/after interpretations, a simple
  preservation convenience, all-outcome obligations and inhabited starting states.
- Kernel replay, foundational-axiom allowlist, sealed generated schema and candidate
  compilation, protected transitive source/schema hashes, process isolation.
- Ordinary CREATE and nullable ADD, retained supported baseline constraints/indexes,
  and explicit bounded transaction/literal-write semantics. General allowed-failure
  and schema-policy examples remain available; no implicit framework behavior.
- Reusable multi-statement examples, checked refutation, native/model and upstream
  fixture evidence with explicit denominators and exclusions.
- Tiny Nix environment source boundary, resource preflight, incremental parser
  builds, single-run evidence collection and scoped/cancellable ordinary CI.
- Native macOS/Linux runtime packaging, offline installation with exact runtime
  roots, installed-entrypoint tests and tag-triggered checked releases.

The business reader must be defined for every admitted state and cannot receive
a proof-only original database. Equality protects the chosen business information;
it does not establish agreement with arbitrary future application queries, new
feature correctness or byte-for-byte storage identity. Current Atuin equality
retains list order. Native conformance is tested/documented, not a proof of SQLite C.
Concurrency, resource failures and crash recovery remain outside the fixed model.

## Validation and release checkpoints

- Earlier engineering preview v0.1.0-rc.1 was published after both platform and
  installed-runtime jobs passed at c840b0434186. It is not evidence for later code.
- SQL-only typed-model checkpoint 19266332 had a successful local offline installed
  runtime test; the later preservation simplification has fresh source checks.
- Current source checkpoint 0c5bb79e: full local `just check`, exit 0, including
  grammar/native/model/Atuin coverage, kernel gate, compilation isolation, public
  CLI, both Atuin positives and eleven negatives, and 36 Python unit tests.
  Evidence: build/preservation-check.log and the
  [preservation status](20260925-business-preservation.status.md).
- Independent technical/conformance review found no blocking proof or packaging
  defect. Hosted full package run36138251243 now passes on both declared platforms at
  e8502876, including offline installed-entrypoint checks. Stable publication
  remains in progress under the separate release record.

Public repository: vihren-dev/sqlite-verifier. Owner authorization includes public
publication and integration of the reviewed protected baseline. Existing branch
rules and target-owned baseline enforcement remain enabled; intentional approved
changes use the owner's existing audited bypass, not weakened checks.

## Remaining completion work

Complete hosted platform/release validation, verify the published artifacts, then
record exact revision/run/release identities and mark this task DONE. No additional
product-owner decision or new pilot is outstanding. Step 2 remains future work and
is not started automatically by completing Step 1. Earlier detailed chronology is
retained in Jujutsu history and the component status files.
