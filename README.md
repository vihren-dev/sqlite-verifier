# SQLite migration verifier

An in-development Lean verifier for SQLite schema extensions. The engineering
contract is in [the brief](sqlite-migration-verifier-engineering-brief.md), with
acceptance tracked in [the Step 1 task](plans/20260924-step-1-schema-extensions.task.md).
The current CLI verifies the documented schema-extension subset. Step 1 acceptance
still requires release evidence and an actual pilot; the checked-in examples are
engineering demonstrations.

## Development

Install Nix with `nix-command` and `flakes` enabled, then enter:

```sh
nix develop
just setup
just check
```

Alternatively, install direnv with Nix-flake integration and run `direnv allow`.
The committed lock fixes Nix dependencies. Nix supplies elan; `just setup`
downloads the exact official Lean release in `lean-toolchain` into elan's cache.
That initial installation needs network access. No Mathlib is required.

The supported development systems are Apple Silicon macOS (`aarch64-darwin`)
and Intel/AMD Linux (`x86_64-linux`). Lean is pinned to 4.33.0; native SQLite is
built from the official 3.51.0 autoconf archive with its default configuration
and readline disabled. `nix build .#sqlite` builds that engine independently.
SQLite's compile settings can be inspected with `sqlite3 :memory: 'PRAGMA compile_options;'`.
These native checks are evidence, not a proof of correspondence with SQLite C.

`just build` compiles the upstream-derived parser, public Lean library, and
independent kernel checker.
`just test` runs the available checks; `just check` combines build and tests.
Commands run under explicit timeouts and are also the entry points for CI.
`just package` creates a development source archive in `dist/`; it is not a
user-installable verifier release. Runtime packaging and release instructions
will accompany the checked CLI and its acceptance examples.

## Verify one migration

Inside the development environment, after `just build`:

```sh
bin/migration-check verify --profile 3.51.0 \
  --schema examples/approved/schema.sql \
  --requirements examples/approved/Requirements.lean \
  --interpretation examples/approved/Interpretation.lean \
  --migration examples/add_column_then_table/migration.sql \
  --next-interpretation examples/add_column_then_table/NextInterpretation.lean \
  --proofs examples/add_column_then_table/Proofs.lean \
  --format json
```

Exit zero means the exact generated verification contract passed independent
kernel replay and dependency checking. Human-format success is silent; JSON
reports `VERIFIED`. `VIOLATED` requires a checked negative theorem. Missing,
rejected, or unfinished proofs are `UNVERIFIED`; unsupported SQL/configuration
and invalid input have separate diagnostics.

`--artifacts NEW_DIRECTORY` exports `SqlInputs.lean`, the target convenience
module `Generated.lean`, and exact input/dependency hashes. It does not create an
approval or a certificate. Once reviewed and protected by the caller,
`--approved-baseline inputs.json` requires the same approved Lean source closure,
including transitive dependencies. That baseline compares only `approved/` Lean
hashes; SQL and profile are bound to each invocation separately. Protect the
baseline, trusted verifier installation, and any additional desired inputs in
the calling project/CI.

Start with the [examples](examples/README.md), [semantic subset](docs/semantic-subset.md),
[fixed execution profile](docs/execution-profile.md), and
[trust boundary](docs/trust-boundary.md). General logical predicates and
interpretations remain available beneath the named-projection helpers.

## License

Project code is MIT licensed. SQLite is upstream public-domain software. Lean
and Nix dependencies retain their respective upstream licenses.
