# Linux sandbox loader regression

Created: 2026-09-24. Status: IN PROGRESS pending packaging integration and hosted rerun.
Task: [Step 1](20260924-step-1-schema-extensions.task.md).
Owner: integration engineer (diagnosis/regression); technical lead (runtime implementation).

Hosted run `35991726213` at `c2288ede` passed macOS, but Linux failed at the first
sandboxed Lean `--deps-json` with bubblewrap execvp ENOENT. Earlier unsandboxed
build/proof suites passed. That revision already preserved `/lib64` aliases.
The pinned Nixpkgs elan package patches downloaded Linux executables' interpreter
to `stdenv.cc`'s exact Nix dynamic-loader path; the sandbox omitted that path.

The lead's shared native-dependency collector now supplies both packaged and
development runtimes. `just build` emits project-owned `build/nix-runtime-roots`;
compilation and checker sandboxes consume only exact validated store roots,
without making the entire store readable.

`tests/test_native_dependencies.py` passed both tests in 0.080 seconds under a
15-second timeout in Nix against the coordinated formal-workspace implementation.
It covers Linux ldd interpreter references, bundled library symlinks, unresolved
and foreign references, development metadata lookup, both sandbox consumers,
and installed-manifest precedence. Linux execution is still a hosted-CI check;
these cross-platform regressions do not claim a Linux end-to-end pass.

Lead integration rechecked all three loader/metadata regressions after adding
explicit broad/ancestor/non-store-root rejection. The source writer records zero
extra roots on macOS, and the actual CLI positive example returns VERIFIED with
the resulting source manifest. The earlier shared macOS suite passed; hosted
Linux evidence remains pending this correction.

## 2026-09-24: non-ELF library names

Hosted run `35993515065` at `bc1b02c8` next failed during loader collection:
`ldd` rejected Lean's `lib/libc++.so` as not a dynamic executable. Library-name
suffixes also match linker scripts. Linux collection now reads only the first
four bytes and inspects ELF library candidates; explicit executables are still
inspected strictly. Versioned libraries and symlinks to ELF libraries remain
included. The regression supplies a textual linker script beside an ELF-header
versioned library and verifies the exact inspection set. Unresolved and foreign
references still reject.

`nix develop --command timeout 15 python3 -m unittest tests.test_native_dependencies`
passed all three tests in 0.077 seconds. The initial real collector invocation
found this workspace's parser artifact absent; the shared `just build` recipe
was then used to produce local artifacts and exercise the real collector.
Hosted Linux end-to-end confirmation remains pending; no successful Linux run
is inferred from these classification regressions.

The shared `nix develop --command timeout 180 just build` passed on macOS,
including the actual collector (zero additional store roots). Linker warnings
about Lean's prebuilt static objects targeting newer macOS were emitted; the
build completed successfully. Local code correction is DONE; hosted evidence
remains pending the new revision.
