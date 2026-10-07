# Checked API documentation and reference

Status: IN PROGRESS. Created 2026-10-06.

Historical implementation and native builds pass at mixed-source checkpoint
`dac12b493dc5b64f5381b8a39fd6ac285b2d5c9b`. Clean isolation, new native reference
builds and hosted artifact acceptance remain required. Historical receipts do
not establish acceptance of the isolated source. See the status file.

## Outcome

The public Lean library has documentation that Lean checks when it compiles
the declaration. Public declarations and fields use Verso documentation with
checked names, terms and computed assertions. The text states the meaning,
provides an example where useful, and explains the value to use when the user
does not need an optional feature. It uses the existing API names.

Core and public propositions state their actual quantifiers, assumptions,
conjuncts and vacuous cases in plain words. These statements follow the
formula, including any case in which it requires nothing. Reusable library
theorems and proofs longer than about 20 lines have a short proof sketch.
The formulas, runtime behavior and verification statuses remain unchanged.

A checked module walkthrough shows how to use the library. CLI help explains
user knowledge that does not belong to a Lean declaration. The README links
to the reference and CLI help. The reference builds under Lean 4.34.1 in CI
from an exact Nix-pinned doc-gen4 and dependency closure. Hosting is not part
of this task. Documentation dependencies belong to the development and
reference build, rather than the installed proof runtime.

Source: [issue #26](https://github.com/vihren-dev/sqlite-verifier/issues/26).
Rules: [checked public documentation and propositions](../AGENTS.md).
Predecessors: the Lean 4.34.1 upgrade and documentation rules. Their checked
implementation is the base for this branch; the upgrade's final owner review
and release remain separate acceptance gates.

## Acceptance

The public entry point and its exported library modules compile with checked
documentation on every public declaration and field. An inventory identifies
the declarations, proposition statements and checked examples, so missing
documentation is visible. The walkthrough and reference examples compile.
Negative fixtures demonstrate that an unknown name, an ill-typed example and
a false checked assertion each fail compilation at their source location.
Each fixture has a short timeout.

The reference build runs in a Nix sandbox without fetching dependencies from
Lake. The output contains the public modules, declaration documentation and
walkthrough, with valid local links. CI builds and retains this output under
the upgraded toolchain on both supported platforms. Ordinary affected checks
and independent commit reviews pass. Documentation examples cannot introduce
new verification semantics or a second proof-checking path.

## Constraints and relevant files

`SqliteVerifier.lean` imports the public library, including model, execution,
contracts, reusable proof helpers and examples. The corresponding files in
`SqliteVerifier/` contain approximately 188 top-level declarations before field
and constructor expansion. Several existing modules are large; documentation
must keep their dependency ordering and type meanings clear.

Checked references cannot name declarations defined later in the same file.
Module walkthroughs can follow their referenced declarations. The public
library import graph and existing flexible constructors remain available;
documentation conveniences cannot replace those primitives. Vocabulary from
unapproved issue #28 is not adopted.

`lakefile.toml`, `build-support/default.nix`, `build-support/sources.nix` and
`.github/workflows/ci.yml` define the build boundary. Exact dependency revisions
must be retained through Nix, including any native library used by doc-gen4.
The reference must not depend on a Git checkout or network access inside its
sandbox. Source links must identify actual repository paths and revisions.

The verified upstream doc-gen4 tag `v4.34.1` resolves to commit
`953c8992d174b4e56955e01e101d46668c68f2bb`. Its own manifest determines the
dependency revisions; no dependency branch tip is used as a pin.
