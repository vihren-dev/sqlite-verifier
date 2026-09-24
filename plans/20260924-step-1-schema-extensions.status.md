# Step 1 status

Created: 2026-09-24. Status: IN PROGRESS — not DONE.

Task: [Verified SQLite schema extensions](20260924-step-1-schema-extensions.task.md).

## References

- [Engineering brief](../sqlite-migration-verifier-engineering-brief.md)
- [Roadmap](../sqlite-migration-verifier-roadmap.md)
- [Team agreement](../sqlite-migration-verifier-team-guide.md)
- Governing workspace rules: `/Users/tzankomatev/work/AGENTS.md`.

Current integrated sources: `flake.nix`, `justfile`, the Lean library entry point,
`migration_check/sandbox.py`, the upstream-derived parser, CI workflow, and their
checks under `tests/`. Formal-core and proof-gate work proceeds in isolated
workspaces until reviewed integration.

## Roles for this work

- Product owner: Tzanko Matev, through the current project conversation.
- Technical/formal-methods lead: `technical_lead`, GPT-6 Astra, Ultra reasoning.
  Owns formal architecture and integration acceptance.
- SQLite/conformance reviewer: `conformance_review`, GPT-6 Astra, Medium reasoning.
  Independently challenges semantic claims and native evidence.
- Coordinator: root agent, responsible for repository setup, durable records,
  and product-owner communication. Product/integration engineering uses Medium
  or lower reasoning for bounded implementation assignments.

Authors do not accept their own substantive changes. Implementation assignments
will name a qualified challenger and a base revision. Additional `jj` workspaces
may live under `~/work`; the technical lead owns integration into `main`.

## Evidence and progress

- The user saved engineering brief revision 0.5, roadmap proposal v0.1, and team
  guide version 0.2 into the initialized `jj` repository.
- Both reviewers read the documents independently. Neither found a demonstrated
  specification contradiction. Full grammar targeting does not require full
  semantic coverage in Step 1.
- Environment preflight found Nix, direnv, just, Lean, Lake, elan, GitHub CLI,
  and SQLite. The Nix daemon responds outside the execution sandbox; the sandbox
  denial was resolved through the normal escalation mechanism.
- Observed installed Lean version: 4.33.0. Observed system SQLite version:
  3.51.0 with an Apple build identifier. Neither observation selects the project's
  pinned toolchain or engine build.
- GitHub CLI authentication is available. `vihren-dev/sqlite-verifier` did not
  exist during preflight; it was subsequently created with explicit owner approval.
- Recorded the Step 1 observable acceptance criteria, required verification
  suite, and implementation constraints before coding.
- At the initial planning checkpoint, no implementation checks had run.

## Independent review findings

The conformance reviewer identified required adversarial coverage: case-insensitive
name collisions, `IF NOT EXISTS` against incompatible tables, rowid shadowing,
partial script success, and changed transitive requirement dependencies.
Applicability must be nonvacuous; whole-script atomicity must not be inferred
from a single input file. Existing-schema dependencies need admission checks.

Both reviewers identified the pilot as a completion dependency. Synthetic
examples are useful engineering checks but do not satisfy the roadmap's real
pilot use and human-effort evidence. This is an input need, not a contradiction
or an environmental blocker.

The technical lead independently reviewed the task/status records against all
three source documents. The acceptance criteria are faithful; the changed-input
test explicitly concerns stale or mismatched proofs, not legitimate newly proved
migrations. This initial commit records planning and review only.
The conformance reviewer separately checked the provisional contract below and
found no blocking objection; prefix guarantees apply to modeled statement errors.

## Provisional pilot contract and proof architecture

These are technical proposals for review, not owner-approved requirements or
implemented guarantees. Ground the exact supported schema in real pilot input.

- Reuse approved logical requirements across actual ordinary-table creation and
  nullable-column additions. A minimal addition has an implicit NULL default;
  other defaults, generated columns, checks, references, and relevant unmodeled
  dependencies remain unsupported until their behavior is established.
- Preserve every approved row identity and designated old field value for
  arbitrary admissible data. New columns read NULL. Required target tables and
  columns are explicit; preservation does not promise unchanged `SELECT *`.
- Proposed initial execution policy: no ambient transaction; execute statements
  in order and stop on the first error. For modeled statement errors, a later
  failure retains the committed successful prefix. Explicit transactions may
  initially be unsupported.
  Concurrency, resource failures, and crashes need explicit profile boundaries.
- Define supported statements and ordered success/failure transitions in Lean,
  then derive schema and projection-preservation lemmas. Retain general logical
  predicates and interpretation primitives beneath keyed-table conveniences.
- Generate the exact theorem from the parsed inputs and profile; check its proof
  and transitive dependency/axiom policy. Use the pinned grammar for recognition
  independently of the smaller semantic subset and retain source locations.
- A useful pilot contract can require successful applicability for every admitted
  starting state as well as outcome coverage and failure safety. This stronger
  guarantee is a proposal, not a universal rule imposed by the engineering brief.

## Product-owner input needed

Identify the first pilot and provide the existing schema, representative actual
table-creation/nullable-column migrations, and the properties that must be
preserved. A path to a local project or sanitized SQL is sufficient for the
team to inspect; the team can help formalize the requirements. The owner can act
as the pilot and later perform the acceptance session.

If no actual pilot material is available, changing the completion criterion to a
demonstration-only release requires an explicit owner decision and corresponding
roadmap update. Do not silently make that substitution.

The initial pause incorrectly treated final pilot evidence as a prerequisite to
all engineering. The source documents do not require that dependency. Engineering
continues with clearly labeled examples; real pilot evidence and owner review
remain required before Step 1 is complete. No product requirement was waived.

## Current work

The Ultra technical lead is defining the formal core and shared interfaces.
The Medium conformance engineer is evaluating upstream grammar reuse and native
evidence. Repository/environment setup can proceed independently of pilot input.
Material product tradeoffs and genuine environment/specification blockers still
require a product-owner sync; routine implementation choices do not.

## Integrated engineering evidence

- The owner explicitly authorized creating and publishing the public GitHub
  repository. `origin` is `git@github.com:vihren-dev/sqlite-verifier.git`; the
  published planning baseline was verified on its `main` branch.
- The lead accepted foundation `2eb0b74a` after independent coordinator review
  and a reproduced `nix develop --command just check` on aarch64-darwin. It pins
  Lean 4.33.0 and upstream SQLite 3.51.0, includes the MIT license, and provides
  source packaging. It is not yet an installable migration verifier.
- Proof-process containment uses macOS Seatbelt or Linux bubblewrap, disjoint
  input/output trees, a fresh environment, timeouts, and bounded captured output.
  The macOS regression demonstrates approved-input write denial, unrelated-data
  read denial, network denial, forbidden subprocess creation, output limits, and
  timeout handling. Linux isolation and descendant cleanup await hosted CI.
- Independent containment review found overlapping read/write trees and
  unbounded output as actual risks; both were corrected and regression-tested.
  Parent only admits trusted Lean search-path environment settings. Containment
  is one part of the trust boundary, not evidence of proof acceptance.
- Limits currently bound each file to 16 MiB and each returned output stream to
  1 MiB. They do not claim a total-disk quota or VM-level resource isolation.

## Remaining work

The lead authorized integration of parser `2f5a83f5`, containment `84596cfc`, and
CI `3fac0a6a` after independent review. Shared checks now compile the pinned
upstream grammar/tokenizer and test syntax families, malformed input, limits,
and UTF-8 source spans. CI runs shared checks on aarch64-darwin and x86_64-linux;
hosted results are pending. Development source archives exclude generated builds.
The integrated `nix develop --command just check` passed on aarch64-darwin:
parser build/20 grammar scripts and boundary cases, Lean build, pinned native
smoke, and real macOS isolation regression (0.618 seconds).

The production CST translator now admits the documented canonical-type subset,
checks all starting-schema dependencies, preserves UTF-8 spans, and computes the
same ordered schema/error prefix. Independent conformance review found no
blocker after 12 admission attacks, 10 native quoted-identifier comparisons, and
exact Lean string-escaping checks. Three regression methods exercise supported
multi-statement input, 29 unsupported forms/dependencies, and parser failure
classes. This unit generates sealed SQL source but does not itself accept proofs.
The combined local suite passed (four unittest cases, 0.807 seconds).

First hosted integration run: macOS passed. Linux correctly denied a write to a
protected input with `EROFS`; the regression expected only `PermissionError`.
The test now accepts the actual read-only-filesystem denial explicitly while
still failing if a write succeeds. Linux will be rerun; no platform pass is
inferred from this diagnosis.

Formal-core integration, CLI semantic admission, proof checking, conformance
corpus, protected CI baseline, installable releases, approved pilot requirements,
pilot evidence, and completion review remain.
