# Immutable project builds

Run `nix-build build-support/default.nix -A runtime --no-out-link` with Nix's
`flakes` experimental feature enabled (`builtins.fetchTree` needs it). This is an
ordinary Nix expression, not a root flake. The development environment remains
exactly `nix/flake.nix` and `nix/flake.lock`; enter it only as `path:./nix`.

Targets `leanToolchain`, `parsers`, `leanRuntime` and `runtime` share the locked
nixpkgs input. Derivations build offline after their declared archives/packages
are fetched. Lean is exactly 4.33.0; neither Elan nor a nixpkgs Lean version is
used. Linux binaries use the pinned loader via autoPatchelf. Darwin upstream
binaries already use bundled-relative/platform loaders.

`parsers/build/` retains both executables, Lemon tools and generated grammar for
fresh host coverage. `leanRuntime/.lake/build/` contains the current Lean library
and checker. `runtime/` assembles those outputs, source/module membership,
examples, Python CLI and exact native loader metadata. It never caches a user
proof verdict or host sandbox/conformance/installed test result. Set
`SQLITE_VERIFIER_RUNTIME_ROOT` to this immutable output before `just test` or
`just package`. Fixtures make private writable copies of examples; reports remain
in the checkout's `build/`, so the runtime itself needs no mutable staging copy.

`just test-cases tests/test_source_identity.py` checks each declared input through
real Nix source identities. Each declared input relation and component-level
ignore rule is selectable; cases cover additions, edits, renames, deletions and
missing required inputs. The
ordinary source suite runs them on both native platforms. Fixtures contain tiny
synthetic inputs; they never copy a checkout or build a package.

Archive digests were taken from the official GitHub v4.33.0 release asset metadata
and verified by downloading both actual native archives on 2026-09-28. Darwin
native graph/build/loader checks passed locally; Linux execution remains a native
CI requirement. Evaluating its derivations on Darwin is not Linux validation.

`unitChecks` uses the same pinned Python/pytest as the development shell and runs
only exact node IDs in `unit-cases.json`. Each case has been reviewed for complete
source inputs and synthetic/mocked dependencies. Collection is checked before
fixture setup: every selected node must be unit-level with no resource markers.
Every selected setup/call/teardown must then pass; skipped or missing cases reject
the derivation. Outputs retain `catalogue.json`, `unit-cases.json`, and
`source/unit.xml` plus `source/unit.json`. Actual proof acceptance, native
conformance, installer/Nix services, host sandbox tests and whole-repository docs
validation are excluded and still execute freshly on the host.
