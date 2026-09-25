# SQLite migration verifier

A Lean verifier for preserving business information across SQLite migrations. The engineering
contract is in [the brief](sqlite-migration-verifier-engineering-brief.md), with
acceptance tracked in [the Step 1 task](plans/20260924-step-1-schema-extensions.task.md).
The CLI verifies the documented schema-extension subset. The owner accepted the
source-backed Atuin case study and preservation contract on 2026-09-25; see the
[acceptance review](docs/atuin-pilot-review.md). Native release artifacts pass
cross-platform validation and installed-package tests before publication.

## Install

Native archives support Apple Silicon macOS and x86_64 Linux. They include the
pinned Lean runtime and an offline Nix cache; Nix must already be installed.
Follow [the installation guide](docs/install.md), then try the bundled examples.
[GitHub Releases](https://github.com/vihren-dev/sqlite-verifier/releases) publishes
archives only after both platform checks and extracted-installation tests pass.
Prereleases are engineering previews; product acceptance is recorded separately.
The first checked preview is [v0.1.0-rc.1](https://github.com/vihren-dev/sqlite-verifier/releases/tag/v0.1.0-rc.1).

## Development

Install Nix with `nix-command` and `flakes` enabled and a bootstrap Python 3,
then enter the development environment once for a batch:

```sh
python3 tools/check_resources.py
nix develop path:./nix
just setup
just check
```

Alternatively, install direnv with Nix-flake integration and run `direnv allow`.
The committed `nix/flake.lock` fixes Nix dependencies. The two-file `nix/`
directory is the complete environment source; always use the explicit `path:`
reference, including from non-Git Jujutsu workspaces. See the
[resource and cleanup policy](sqlite-migration-verifier-team-guide.md#development-resources).
The resource check rejects less than 10 GiB free before expensive work. Nix supplies elan; `just setup`
downloads the exact official Lean release in `lean-toolchain` into elan's cache.
That initial installation needs network access. No Mathlib is required.

The supported development systems are Apple Silicon macOS (`aarch64-darwin`)
and Intel/AMD Linux (`x86_64-linux`). Lean is pinned to 4.33.0; native SQLite is
built from the official 3.51.0 autoconf archive with its default configuration
and readline disabled. `nix build path:./nix#sqlite` builds that engine independently.
SQLite's compile settings can be inspected with `sqlite3 :memory: 'PRAGMA compile_options;'`.
These native checks are evidence, not a proof of correspondence with SQLite C.

`just build` compiles the upstream-derived parser, public Lean library, and
independent kernel checker.
`just test` runs the available checks; `just check` combines build and tests.
Commands run under explicit timeouts and are also the entry points for CI.
`just coverage` refreshes the [bounded coverage report](docs/coverage.md).
`just package` runs the shared checks, builds a native runtime archive in `dist/`,
and tests its actual installed entrypoint before retaining a source snapshot.
See [CI and release procedure](docs/ci.md).

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
including transitive dependencies. The baseline compares `approved/` Lean hashes and, when included, the
`schema.sql` hash; the Atuin baseline protects both. Migration SQL and profile
are bound to each invocation separately. Protect the
baseline, trusted verifier installation, and any additional desired inputs in
the calling project/CI.

The [Atuin example](examples/atuin/README.md) protects the pre-migration history
model while allowing the new schema to evolve. Its contract does not prescribe
the new shell field or verify SQLx bookkeeping.

Start with the [examples](examples/README.md), [semantic subset](docs/semantic-subset.md),
[fixed execution profile](docs/execution-profile.md), and
[trust boundary](docs/trust-boundary.md). General logical predicates and
interpretations remain available beneath the named-projection helpers.

## License

Project code is MIT licensed. SQLite is upstream public-domain software. Lean
and Nix dependencies retain their respective upstream licenses.
