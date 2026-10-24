# Translation dependencies and complete local law checks

Created 2026-10-24. Status: DONE (2026-10-24).
Status file: [status](20261024-text-build-boundaries.status.md).
Audience: implementers and reviewers.
Specifications: [ADR 0016](../docs/adr-0016-model-and-surface.md), D2;
[ADR 0020](../docs/adr-0020-local-build-loop.md).

## Present problem

The owner requested modularity improvements while ADR 0017 is implemented.
`Translation/Located.lean` imports the complete model root. This makes the text
package depend on model proof modules although it translates SQL syntax.
The conformance runner already avoids this dependency through narrower imports.
ADR 0020 records the benefit of keeping proof-only changes out of runner builds.

The local `dev-build` recipe builds only `conformance-runner` in the conformance
package. Its library also contains laws outside the runner's import closure, such
as `RunPassLaws`. Nix builds both `VerifierConformance` and `conformance-runner`.
The local recipe can therefore pass while a model change breaks these laws.
The owner's 2026-10-24 handoff records two full-check failures after omitted law
builds. Correct the existing target list; no separate failure-injection harness
is needed for that recipe change.

## Required outcomes

- The SQL translation program does not transitively import the complete
  `Belay.Sqlite.Model` root or unrelated model proof and example modules through
  that root. The text package still follows ADR 0016's public-root boundary.
  Prefer existing public roots that provide the required declarations. Any
  additional public root has a documented, concrete reader in this package.
- The translation produces the same syntax, source ranges, restrictions and
  errors as before. The parser interface, codec format, SQL semantics, judge
  claims and judge lock stay unchanged.
- `just dev-build` checks the complete conformance library as well as the runner,
  in addition to its current model, text and surface targets. A failure in a
  conformance law outside the runner's closure makes this command fail.
- A second local build with no changed inputs compiles no targets. A model
  proof-only edit outside the translator's import closure does not rebuild the
  translator through the removed umbrella import. Record which edit and command
  establish this; there is no assumed time or percentage improvement.
- Documentation and tests describe these boundaries accurately. Full Nix law,
  documentation and conformance checks retain their coverage.

## Tests and acceptance

- Extend the existing layer tests to detect reintroduction of the model umbrella
  into the translator's transitive import closure, including an indirect import.
  Keep the existing checks of dependency direction and public roots.
- Run the existing local-loop check and inspect the complete conformance library
  build result. Keep subprocess timeouts. This recipe correction needs no new
  temporary-source failure test.
- Run the existing SQL translation, source-position, codec and surface fixtures
  through their Nix suites. Compare the frozen-corpus predictions before and after
  the change; their contents must be byte-identical.
- One slice: after the last code review, `just test-full` and `just verdict`.
  At task completion, `just test-nix` and `just test-scheduled-checks`.
  The owner's 2026-10-24 handoff replaces the older `AGENTS.md` task-end cadence
  with this narrower scheduled recipe and forbids broad local mutant runs.
  No new mutant is required for an unchanged semantic function.
- Commit checks use the existing relevant layer and local-loop tests. Run
  `just dev-build` for package edits. Each commit has an independent review and
  its findings are resolved under the repository process.

## Important constraints

- `tests/surface_layers_test.py` obtains public model roots from the model
  lakefile. A direct import of an internal module must not bypass that rule.
- A codec root can import executable model definitions. This task removes the
  accidental proof dependency; it does not require removing every runtime
  dependency or creating a second codec.
- `tests/dev_loop_test.py` already checks no-op compilation and executable
  startup. Reuse its support instead of adding a parallel build framework.
- Model-only proofs remain in the model. The surface and text package must not
  become dependencies of lower packages.
- Nix currently selects the complete model source as one derivation. This task
  does not promise independent Nix caching for proof edits, split packages, or
  reusable native archives. Those require separate measured justification.
- Work on top of PR #239 in a separate workspace. S4 edits the model and surface;
  coordinate any shared lakefile change with its implementer before writing it.

## Relevant files

`packages/belay-sqlite-text/Belay/Sqlite/Translation/Located.lean`, the translation
modules and program, `packages/belay-sqlite-model/lakefile.toml`,
`packages/verifier-conformance/lakefile.toml`, `justfile`,
`tests/surface_layers_test.py`, `tests/dev_loop_test.py`, and
`build-support/default.nix`.
