# Install the native verifier

Choose the `aarch64-darwin` archive for Apple Silicon macOS or `x86_64-linux`
for Linux x64. Nix must already be installed with its usual trusted cache keys.
Linux also needs working unprivileged user and network namespaces for bubblewrap;
the verifier refuses to run without its sandbox. CI tests macOS 14 and Ubuntu
22.04; the host system loader/kernel remain platform prerequisites.

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
binary cache offline with signature checking enabled, copies the payload, and
creates indirect Nix garbage-collection roots inside the installation. It does
not download Lean, use elan, modify shell configuration, or replace another
installation. The entrypoint uses the pinned Python in isolated mode, bundled
Lean 4.33.0, pinned parser/checker/library, and pinned Linux bubblewrap. Ambient
`PYTHONPATH`, `LEAN_PATH`, and Lean selection do not select its runtime.

Remove the installation directory to uninstall; its indirect GC roots then
expire and ordinary Nix garbage collection can reclaim unused dependencies.
`native-dependencies.txt` records loader references observed during packaging.
The platform's system libraries remain outside this bundle; Nix store loader
dependencies are retained in the offline cache and admitted through exact
packaging-owned `lean/nix-runtime-roots` metadata, never by granting the whole
store to a proof process. The installation and its metadata are trusted code. Source-tree `just build`
writes the equivalent `build/nix-runtime-roots` manifest because Nix-installed
elan may patch the Linux Lean executable to use a Nix store ELF interpreter.

The examples are synthetic engineering cases, not evidence of real-pilot
acceptance. `VERIFIED` applies to the supplied contract and documented restricted
SQL model. See the repository's semantic-subset and kernel-gate documentation.

Nix's [copy command](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-copy)
provides the local binary-cache transport; the installer does not disable its
signature checks. An archive checksum detects corruption; obtain it and the
archive from the project's trusted release location.
