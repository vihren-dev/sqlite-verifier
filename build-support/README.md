# Immutable project builds

Run `nix-build build-support/default.nix -A runtime --no-out-link` with Nix's
`flakes` experimental feature enabled (`builtins.fetchTree` needs it). This is an
ordinary Nix expression. The flake in `nix/flake.nix` also exposes the same test
derivations as `checks.<system>`. The development shell remains
`nix develop path:./nix`, with the existing `nix/flake.lock` pin.

Targets `leanToolchain`, `parsers`, `leanRuntime` and `runtime` share the locked
nixpkgs input. Derivations build offline after their declared archives/packages
are fetched. Lean is exactly 4.33.0; neither Elan nor a nixpkgs Lean version is
used. Linux binaries use the pinned loader via autoPatchelf. Darwin upstream
binaries already use bundled-relative/platform loaders.

`just parser` builds the `parsers` target and links its executables and grammar
directories into the checkout’s `build/`. Nix owns all parser build reuse; there
is no separate local builder or content-stamp cache. The derivation verifies
upstream checksums; `parser/generate.py` verifies token agreement and transforms
the grammar before Nix compiles and links the C sources.

`parsers/build/` retains both executables, Lemon tools and generated grammar for
fresh host coverage. `leanRuntime/.lake/build/` contains the current Lean library
and checker. `runtime/` assembles those outputs, source/module membership,
examples and Python CLI. `just build` uses this same runtime and exposes local development
paths as links; it does not rebuild Lean through Elan or Lake outside Nix. It never caches a user
proof verdict or installed test result. Set
`SQLITE_VERIFIER_RUNTIME_ROOT` to this immutable output before `just test` or
`just package`. Fixtures make private writable copies of examples; reports remain
in the checkout's `build/`, so the runtime itself needs no mutable staging copy.

`just test-nix` (part of `just package`) runs `tests/test_source_identity.py`, which
checks each declared input through real Nix source identities. Each declared input relation and component-level
ignore rule is selectable; cases cover additions, edits, renames, deletions and
missing required inputs. CI runs
them on both native platforms whenever packaging is selected. Fixtures contain tiny
synthetic inputs; they never copy a checkout or build a package.

Archive digests were taken from the official GitHub v4.33.0 release asset metadata
and verified by downloading both actual native archives on 2026-09-28. Darwin
native graph/build/loader checks passed locally; Linux execution remains a native
CI requirement. Evaluating its derivations on Darwin is not Linux validation.

`tests.kernel`, `tests.model`, `tests.atuin` and `tests.cli` are independent pytest derivations declared in
`tests.nix`. Kernel inputs are the test/Lean fixtures, shared pytest support,
pinned Python/pytest and Lean toolchain/library/checker. Model inputs add its
explicit conformance helpers, Python translator sources, parsers and pinned
SQLite. Kernel/model targets exclude unrelated tests, examples and documentation. Atuin
and CLI each add their test file and the complete runtime (including Python
implementation and examples). Changes to those runtime inputs invalidate both.
Changes to shared pytest support invalidate all four. Nix owns all result reuse.

Run all four checks through the flake:

```sh
nix flake check ./nix -L \
  --option sandbox true --option sandbox-fallback false \
  --extra-experimental-features 'nix-command flakes'
```

Use `./nix` for checks: Nix includes the Git repository, allowing the subdirectory
flake to access project sources above it. `path:./nix` copies only that directory
and is suitable for the standalone development shell, not project checks.
`--no-build --all-systems` evaluates both platforms without running their tests.

The installed Nix 2.18 cannot create result links from `flake check`, so `just test`
builds the same derivations with `nix-build -A tests`, retaining outputs under
`build/nix-tests*` for CI reports. `just test-atuin`
selects only Atuin. `just test-cases tests/kernel_gate_test.py` forces an ordinary
pytest run. The non-flake `nix-build -A tests.kernel` entrypoints remain available.
On a miss, the target runs pytest and saves `junit.xml` under its output.
On a hit, Nix reuses the successful output; no pytest process runs. Failed pytest executions fail the derivation.

Keep sandboxing enabled for these builds, including manual invocations. This is
explicit in the recipe and CI configuration because Nix defaults differ by OS.
Sandboxing blocks undeclared checkout inputs; it is not a guarantee against
nondeterminism from clocks or platform behavior. Nix daemon tests and installed acceptance remain fresh host executions.

Offline archives export the complete runtime using `nix store make-content-addressed`
and `nix copy`. The installer verifies imports, creates a GC root and links the
installation to the imported immutable runtime. It needs no extra signing key,
loader scan, copied Lean subset or ELF relocation. Installed acceptance still
executes freshly against the resulting content-addressed runtime.
