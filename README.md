# SQLite migration verifier

An in-development Lean verifier for SQLite schema extensions. The engineering
contract is in [the brief](sqlite-migration-verifier-engineering-brief.md), with
acceptance tracked in [the Step 1 task](plans/20260924-step-1-schema-extensions.task.md).
This foundation alone does not provide a migration-verification command.

## Development

Install Nix with `nix-command` and `flakes` enabled, then enter:

```sh
nix develop
just setup
just smoke
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

`just build` compiles the public Lean library entry point. Its formal modules
are supplied by the formal-core change; the initial entry point contains no claims.
`just test` runs the available checks; `just check` combines build and tests.
Commands run under explicit timeouts and are also the entry points for CI.
`just package` creates a development source archive in `dist/`; it is not a
user-installable verifier release. Runtime packaging and release instructions
will accompany the checked CLI and its acceptance examples.

## License

Project code is MIT licensed. SQLite is upstream public-domain software. Lean
and Nix dependencies retain their respective upstream licenses.
