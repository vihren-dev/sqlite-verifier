# Install the native verifier

Choose the `aarch64-darwin` archive for Apple Silicon macOS or `x86_64-linux`
for Linux x64. Nix must already be installed. Import verification remains enabled.
CI tests macOS 14 and Ubuntu 22.04; the host system loader/kernel remain platform
prerequisites. Lean source executes with the caller’s permissions. Only run source
you trust; the verifier supplies no OS sandbox. See the [trust boundary](trust-boundary.md).

Check the archive against its accompanying SHA-256 file, extract it, and run:

```sh
./install.sh "$HOME/.local/opt/sqlite-verifier"
"$HOME/.local/opt/sqlite-verifier/bin/migration-check" verify \
  --profile 3.51.0 \
  --schema "$HOME/.local/opt/sqlite-verifier/examples/approved/schema.sql" \
  --requirements "$HOME/.local/opt/sqlite-verifier/examples/approved/Requirements.lean" \
  --interpretation "$HOME/.local/opt/sqlite-verifier/examples/approved/Interpretation.lean" \
  --migration "$HOME/.local/opt/sqlite-verifier/examples/add_column_then_table/migration.sql" \
  --next-interpretation "$HOME/.local/opt/sqlite-verifier/examples/add_column_then_table/NextInterpretation.lean" \
  --proofs "$HOME/.local/opt/sqlite-verifier/examples/add_column_then_table/Proofs.lean" \
  --format json
```

The destination must not exist. Installation imports the included local Nix
binary cache offline with verification enabled, links to the immutable runtime, and
creates indirect Nix garbage-collection roots inside the installation. It does
not download Lean, use elan, modify shell configuration, or replace another
installation. The entrypoint uses the pinned Python in isolated mode, bundled
Lean 4.34.1, pinned parser/checker/library.
Installed files are immutable Nix outputs; copy examples elsewhere before editing them. Ambient
`PYTHONPATH`, `LEAN_PATH`, and Lean selection do not select its runtime.

Remove the installation directory to uninstall; its indirect GC roots then
expire and ordinary Nix garbage collection can reclaim unused dependencies.
The archive contains the complete runtime closure, converted with Nix's
`make-content-addressed`. Nix verifies these paths against their content hashes;
project outputs need no additional trusted signing key. Signature checking is
never disabled. As before, verify the downloaded release archive's checksum:
content addressing establishes byte identity, not publisher identity.

To prepare a proof separately and check it without compiling candidate source,
use the [data path](data-path.md) commands from the same installation:

```sh
V="$HOME/.local/opt/sqlite-verifier"
E="$V/examples"
"$V/bin/migration-check" prepare --profile 3.51.0 --schema "$E/approved/schema.sql" \
  --requirements "$E/approved/Requirements.lean" --interpretation "$E/approved/Interpretation.lean" \
  --migration "$E/add_column_then_table/migration.sql" \
  --next-interpretation "$E/add_column_then_table/NextInterpretation.lean" \
  --proofs "$E/add_column_then_table/Proofs.lean" --workspace agent-build --output proof.bundle
"$V/bin/migration-check" verify-bundle --profile 3.51.0 --schema "$E/approved/schema.sql" \
  --requirements "$E/approved/Requirements.lean" --interpretation "$E/approved/Interpretation.lean" \
  --migration "$E/add_column_then_table/migration.sql" --bundle proof.bundle --format json
```

The examples include synthetic engineering cases and the source-backed Atuin
case study; its [acceptance review](atuin-pilot-review.md) records owner approval.
`VERIFIED` applies to the supplied contract and documented restricted SQL model.
See the [semantic subset](semantic-subset.md) and [kernel gate](kernel-gate.md).

Nix's [copy command](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-copy)
provides the local binary-cache transport; the installer does not disable its
signature checks. An archive checksum detects corruption; obtain it and the
archive from the project's trusted release location.
