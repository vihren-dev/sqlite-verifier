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
