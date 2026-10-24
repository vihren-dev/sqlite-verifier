# ADR 0020: A local incremental build loop for model work

Date: 2026-10-21. Status: ACCEPTED (2026-10-22).
Changed 2026-10-21: the toolchain comes from a root `shell.nix`; executables link for the
Nix loader through `LEAN_CC`; `just build` no longer links its runtime into the checkout,
so the local loop builds in `packages/`.
Changed 2026-10-22: based on the layout of ADR 0021 and the text package (pull requests
#209 to #212). The targets, the runtime root, the shell's parser library and the
measurements follow that layout. Later the same day: agent sessions load `.envrc` through
direnv (fact 8), so D1, D5 and D6 rely on it; owner decisions 2 and 3 are decided.
Changed 2026-10-24: D2 includes the complete conformance library and the text
package's narrower model dependency.
Initial implementation: one task file and one pull request; the task is
[`plans/20261022-local-build-loop.task.md`](../plans/20261022-local-build-loop.task.md).
The 2026-10-24 correction is specified in
[`plans/20261024-text-build-boundaries.task.md`](../plans/20261024-text-build-boundaries.task.md).
Audience: designers and reviewers.
Related: [ADR 0010](adr-0010-lake-builds-and-artifact-cache.md) (Lake builds, one Nix
derivation per Lean package), [ADR 0011](adr-0011-product-trust-and-development-integrity.md)
(the judge; a local result decides nothing), [ADR 0016](adr-0016-model-and-surface.md)
(the model and the surface), [ADR 0021](adr-0021-remove-the-verifier-product.md) (the
removal of the verifier product). Earlier measurements:
[`experiments/dev-loop-cost/README.md`](../experiments/dev-loop-cost/README.md).

## Overview

While an agent edits the model, it checks each edit with a Nix build. Nix builds a Lean
package as one derivation, so each edit to a model module recompiles the whole model
package, then the packages that require it. This ADR adds a second way to check an edit:
a local Lake build that compiles only what changed, in a development shell with the same
pinned toolchain and parser library, and a local judge run over the corpora with the
programs from that build. Nix stays the only source of evidence. The local loop gives
feedback while an agent edits; the Nix checks run at the points that `AGENTS.md` gives
(D5), and CI runs them as today.

## Context

### The problem: the Nix build is the edit loop

In the Claude Code development session from 2026-10-09 to 2026-10-21, foreground
conformance builds (`nix-build -A conformance` and its recipes) took 462 calls and 5.8
hours, and `just test-full` 165 calls and 7.6 hours (`experiments/dev-loop-cost/README.md`).

Measured 2026-10-22 on one Linux x86_64 host (8 CPUs, load average 3 to 5), on the top of
pull request #212 with the commits of this ADR's branch. Each edit appends one
definition to a module, then the build runs:

| Edited module | `nix-build -A conformance` | Local `lake build conformance-runner` |
| --- | --- | --- |
| None (no-op) | | 0.1 s, 0 jobs |
| `VerifierConformance.Json` (runner) | | 4.0 s, 5 jobs |
| `Belay.Sqlite.Model.QueryLaws` (proofs) | | 0.1 s, 0 jobs |
| `Belay.Sqlite.Model.QueryFunctions` (middle) | 133.2 s | 13.5 s, 30 jobs |
| `Belay.Sqlite.Model.Identifier` (many dependents) | | 40.6 s, 165 jobs |

The local programs and the Nix-built ones give byte-identical predictions for all 48 judge
input files (7,215 cases). A local `python -m judge run` with the local programs took
61 s and gave the same verdict counts as `just verdict` for all 48 corpora.

The commit `perf: import only the model's definitions in the codec` (on the branch of
this ADR) removes the 32 proof modules from the runner's import closure (216 to 182
modules). The times above include it. This ADR does not depend on it.

### Facts that constrain the design

1. **The flake dev shell cannot get the pinned toolchain; a `shell.nix` can.**
   `nix/flake.nix` provides `just`, Python with pytest, the SQLite builds and `patchelf`.
   The pinned toolchain is `leanToolchain` in `build-support/default.nix`. The flake's
   source is the `nix/` directory, and pure evaluation forbids paths outside it:
   `nix eval path:./nix#checks.x86_64-linux.model.drvPath` failed with "access to
   absolute path '/nix/store/build-support/default.nix' is forbidden in pure evaluation
   mode". `nix-shell` evaluates a `shell.nix` without this restriction. The trial
   `shell.nix` at the repository root imports `build-support/default.nix`, puts the same
   toolchain store path on `PATH` as the Nix builds use, and loads in about 4 s.
   `build-support/locked-nixpkgs.nix` reads the nixpkgs pin from `nix/flake.lock`, so
   both shells get the same packages.
2. **`just build` no longer links its runtime into the checkout.** Before the commit
   `build: use build/conformance as the runtime root and stop linking it into the
   checkout` (on the branch of this ADR), `just build` replaced `.lake/build` and
   `packages/belay-sqlite-model/.lake/build` with links into the read-only runtime in the
   Nix store, and linked `lean`. `just test` and `just test-full` run it first, so a local
   `lake build` in `packages/` then failed: on 2026-10-21, clang reported "Permission
   denied" for each output file under the model's `.lake/build/ir`. The links served one
   purpose: the checkout was the default runtime root of the host tests, as ADR 0001
   decided when Lean was built in the checkout. The tests do not need them. With the
   commit, the test recipes default to `build/conformance`, and `just test-full` and
   `just test-nix` pass. After it, local builds in `packages/` succeed, and a local build
   after `just build` compiles nothing.
3. **Lake builds incrementally.** Lake compares hashes, not file times: a `touch` of a
   source file compiled 0 jobs (measured 2026-10-21). The table above shows the jobs of
   real edits.
4. **Lake's default link gives programs that do not start on NixOS.** Lake compiles and
   links with the toolchain's bundled clang, which links for the loader
   `/lib64/ld-linux-x86-64.so.2`. NixOS does not have it, and the Nix build fixes the
   outputs with `autoPatchelfHook`. When `LEAN_CC` is set, Lake calls that program
   instead, and it no longer adds the toolchain's own flags. Others use this: the nixpkgs
   `elan` package sets `LEAN_CC` to the Nix C compiler wrapper, and lean4-nix replaces
   the bundled clang and linker with Nix-wrapped ones (sources below). Measured relinks of
   the runner on 2026-10-21:

   | Link | Relink | Starts on NixOS |
   | --- | --- | --- |
   | Lake's default, the bundled clang | 0.6 to 0.9 s | No; `patchelf --set-interpreter` makes a copy start |
   | `LEAN_CC` = the Nix GCC wrapper, as nixpkgs `elan` does | 35.8 s | Yes |
   | `LEAN_CC` = the Nix clang wrapper with lld, as lean4-nix does | 9.1 s | Yes |
   | `LEAN_CC` = the bundled clang with the toolchain's flags and the Nix loader | 0.8 s | Yes |

   The last wrapper adds, for a compile (`-c`), `--sysroot`, `-nostdinc` and the bundled
   C headers; for a link, `--sysroot`, `-fuse-ld=lld`, the bundled `lib` and
   `lib/glibc` directories, the two glibc `_nonshared` archives, the static unwinder and
   `--dynamic-linker` with the loader of the Nix C compiler. These flags copy flags that
   are built into the toolchain, so a Lean upgrade can change them. Inside the trial
   `shell.nix`, on 2026-10-22, the four Lean packages built in `packages/`: the model
   (56 s) and the text package (44 s) from clean, then the runner (6 s, 19 jobs, over
   older outputs) and the surface (2 s), including the text package's and the surface's
   precompiled shared libraries. The runner and the
   translation program have the Nix loader, and a file that imports `Belay` elaborated
   with the locally built shared libraries, with the module setup that
   `tests/surface_support.py` writes and the libraries' local folders.
5. **The text package reads the parser library when Lake loads it.**
   `packages/belay-sqlite-text/lakefile.lean` reads `BELAY_PARSER_LIBRARY` and stops when
   it is not set. It links the parser library with its folder in the Nix store as the
   run-time search path, so the translation program finds it without a copy.
6. **The runtime root of predict holds two programs.** `python -m conformance.predict
   --runtime ROOT` runs `ROOT/.lake/build/bin/belay-sqlite-translate` to map SQL text to
   statement syntax, and `ROOT/.lake/build/bin/conformance-runner` to run it. A root with
   copies of the two local programs gave the predictions above.
7. **The judge runs without Nix.** `python -m judge run --root . --claims FILE -- COMMAND`
   gives each claimed corpus's inputs to the command and checks the claims. Its claims
   file maps each corpus name to its claim, so a copy with fewer corpora checks fewer.
8. **Agent sessions load `.envrc`, and cannot start a new Nix shell.** Since 2026-10-22
   the owner's user configuration (not this repository) gives each Claude Code session
   the direnv environment of its working directory: a hook runs `direnv export bash`
   when the session starts and each time it changes directory, and the session's later
   commands get the result. A second hook refuses commands that run `nix develop` or
   `nix-shell`, because each call made a new `/tmp/nix-shell.*` directory with its own
   pytest data (30 directories and 6.8 GB on 2026-10-21). direnv loads an `.envrc` only
   after `direnv allow` in that directory, again after each change of the file, and once
   for each jj workspace. The owner runs it; an agent runs it only with the owner's
   permission. Checked on 2026-10-22: after a change into this workspace, a command found
   the dev shell's `just`, `TMPDIR` was not set, and `nix-shell --version` was refused.

## Decision

### D1. A root `shell.nix` with the pinned toolchain and parser library

A `shell.nix` at the repository root is the development shell for the local loop. It
has the packages of the flake dev shell and the toolchain of `build-support/default.nix`.
It sets `BELAY_PARSER_LIBRARY` to `parserLibrary.library` of the same build (fact 5), and
on Linux it sets `LEAN_CC` to the last wrapper of fact 4. The two shells take their
package list from one file under `nix/`, which both can import, so that they cannot
drift apart. `.envrc` loads `shell.nix` (`use nix`), so each agent session that changes
into the repository has the shell of the local loop (fact 8). The flake dev shell stays
for CI, which calls `nix develop path:./nix`, and for users who enter it by hand (owner
decision 3).

The shared file is `nix/dev-shell.nix`. With it, the flake dev shell's derivation did not
change.

### D2. Local builds in `packages/`

The local loop runs `lake build` in the Lean packages under `packages/`, in the shell of
D1. Lake keeps the outputs in each package's `.lake/`, which Git ignores and which
`just build` does not touch (fact 2). A checkout made before the change of fact 2 can
still hold the old links; delete them once (`rm .lake/build
packages/belay-sqlite-model/.lake/build lean` when they are links).

It builds these targets, the ones that model work can break:

| Package | Targets |
| --- | --- |
| `belay-sqlite-model` | `Belay.Sqlite.Model`, `Belay.Sqlite.Model.Codec` (the targets of `modelPackage`) |
| `belay-sqlite-text` | `BelaySqliteText`, `BelaySqliteText:shared`, `parserShim:shared`, `belay-sqlite-translate` |
| `verifier-conformance` | `VerifierConformance`, `conformance-runner` |
| `belay` | `Belay`, `Belay:shared` (owner decision 1, decided) |

The complete conformance library includes laws outside the runner's import closure.
The local loop checks these laws with the same library target as Nix. The text
package imports the model's public codec root, which supplies syntax and resolution
definitions without the model root's proof and example imports.

The documentation tool stays with Nix.

### D3. A local verdict

A recipe builds the two programs of fact 6 as in D2 and makes a runtime root in
`build/dev/runtime/` with copies of them under `.lake/build/bin/`. It then runs the
judge's `run` mode with `python -m conformance.predict --runtime build/dev/runtime` as
the subject, for all claimed corpora or for the corpora named on the command line. It
prints the judge's counts and failures, writes the report to `build/dev/report.json`,
and exits with the judge's exit code.

The recipe does not change `judge/`, `judge/claims.json` or the lock. For a subset of
corpora it writes a reduced copy of the claims file under `build/dev/`.

### D4. Recipes

| Recipe | Does |
| --- | --- |
| `just dev-build` | D2: `lake build` of the targets of D2 in each package |
| `just dev-verdict [CORPUS...]` | D3: `lake build` of the two programs, then the local verdict |

Both are plain recipes that run `lake build`, `cp` and the judge, in the shell of D1.
Outside it they print a warning and run anyway; Lake's own errors show what failed. To
build one target, run `lake build TARGET` in its package. (Amended 2026-10-22 by the
owner: a first version in Python had target arguments and checks before a build, which
no present problem needed.)

### D5. How agents use it

`AGENTS.md` gets a rule for model work: while editing, check edits with the local
loop; before each commit, run the Nix checks that the existing rules require. A local
result is not evidence: commit messages, status files and pull requests cite Nix
results only. This follows ADR 0011: a result on a developer machine decides nothing.
(Owner decision 2.)

Amended 2026-10-23 by the owner: the Nix checks do not run before each commit. A commit
gets the tests that touch it and `just review`; `just test-full` and `just verdict` run
at the end of each slice of a task; `just test-nix` and `just test-scheduled` run once
before the pull requests. The section "Checks and their cadence" of `AGENTS.md` gives
this cadence. The rule "before each commit" made agents run `just test-full`, about 15
minutes, after each commit, and wait for it.

The rule also says that direnv loads the shell (fact 8): agents run `just` and `lake`
directly and do not enter a shell. When a tool of the shell is missing, the agent asks
the owner to run `direnv allow`. Two texts that tell readers to enter the shell change
with it:

- The first comment of the `justfile` says that direnv loads the shell, and names
  `nix develop path:./nix` only for a shell outside direnv.
- The README keeps `nix develop path:./nix` for users. Its direnv sentence says that
  `.envrc` loads `shell.nix`, which needs direnv, and that nix-direnv only caches it.

### D6. Tests

The recipes are our code, and one test checks them. A test marked `requires_nix` (outside the Nix suites, because it needs the shell of D1
on the host) runs in the shell that direnv loaded and does not start a shell itself
(fact 8). It skips with a message when `LEAN_CC` (on Linux) or `BELAY_PARSER_LIBRARY` is
not set. It runs `just dev-build` twice and checks that the second run compiles no job,
checks that the runner and the translation program start (so a Lean upgrade that
changes the toolchain's flags fails here), and runs `just dev-verdict` on one small
corpus and checks exit code 0 and that the report has only that corpus, which also
checks the layout of the runtime root and the reduced claims file. The pull request records one measurement on the same
commit: the counts of `just dev-verdict` equal those of `just verdict`.

## Consequences

- **An edit of a middle model module costs about 14 s instead of about 133 s** before
  the agent sees whether the runner still builds. A local verdict over all corpora took
  61 s.
- **Each jj workspace has its own local outputs.** The first `dev-build` in a workspace
  is a clean build: the model and the text package took 56 s and 44 s in the
  measurement. The outputs of the four packages take about 430 MB.
- **The `LEAN_CC` wrapper copies the toolchain's built-in flags.** A Lean upgrade can
  change them. The `requires_nix` test of D6 and the first local build after the upgrade
  show it, and the upgrade change updates the wrapper.
- **Two ways to build can disagree.** Nothing in the local loop is evidence, and the
  Nix checks at the end of each slice catch a difference. The loop uses the same toolchain,
  parser library and sources, so a difference shows a bug in the loop.
- **The `.envrc` change needs `direnv allow` in each workspace.** Until the owner runs
  it, direnv loads nothing there, and the session has neither the shell of D1 nor the
  flake shell. The agent sees that `just` or `lean` is missing and asks the owner.
- **The Nix CI times do not change.** This ADR changes only the agent's edit loop.

## Alternatives considered

**Add the toolchain to the flake dev shell.** Rejected. The flake cannot import
`build-support/` (fact 1). It would need its own copy of the toolchain pin, which could
differ from the one the builds use, or the flake would have to move to the repository
root. A `path:` flake at the root copies the whole working tree, including `build/`, into
the store at each evaluation, and a `git+file` flake needs a `.git` directory, which
secondary jj workspaces such as this one do not have.

**A copy of the sources in `build/dev/`, built there.** Rejected. It was needed only
while `just build` linked the runtime into `packages/` (fact 2). It adds a sync step
before each build, and Lake's messages then name files in the copy, not the files that
the agent edits.

**`patchelf --set-interpreter` on copies of the programs after each build.** Rejected. It
works (fact 4), but it is one more step after every link, and every tool that starts a
program must use the patched copy.

**`LEAN_CC` set to a Nix compiler wrapper.** Rejected. It needs no copied flags, but each
relink of the runner took 35.8 s with the GCC wrapper and 9.1 s with the clang and lld
wrapper, against 0.8 s, and model edits relink the runner.

**`programs.nix-ld` on the host.** Rejected. It makes generic binaries start on NixOS,
but it is a setting of each machine, outside the repository.

**Add the loader to `moreLinkArgs` in the lakefiles.** Rejected. It would also change the
Nix builds, which already use `autoPatchelfHook`.

**Lean Beam for the edit loop.** Not decided here. Its goal-state and lookup commands
could replace some file reads, which the measurements put at a few percent of the
context. It does not build the programs or run the corpora.

## Not decided here

- Running the Python test suites against the local outputs.
- Sharing local outputs between workspaces, for example with Lake's artifact cache
  (ADR 0010).
- When Claude Code compacts the context. The owner sets this per user
  (`autoCompactWindow`); it is not repository configuration.

## Owner decisions

Decided on 2026-10-22:

1. **The surface package in D2.** The local loop builds it. A model change can break the
   surface, and after the text package it built in 2 s.
2. **The rule of D5.** As written: the local loop while editing, the Nix checks before
   each commit. Amended 2026-10-23: the Nix checks run at the points of the cadence in
   `AGENTS.md` (see D5).
3. **The flake dev shell.** Keep it for CI, with the package list shared with
   `shell.nix`. The rejected alternative replaced it with `shell.nix` everywhere, which
   changes the CI workflows and the README.

## Sources

- nixpkgs `elan`: [package.nix](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/el/elan/package.nix)
  and [the toolchain patch](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/el/elan/0001-dynamically-patchelf-binaries.patch),
  which sets `LEAN_CC` for `lake`.
- lean4-nix: [repository](https://github.com/lenianiva/lean4-nix) and
  [lib/toolchain.nix](https://github.com/lenianiva/lean4-nix/blob/main/lib/toolchain.nix),
  which replaces the bundled clang and linker.
- [nix-ld](https://github.com/nix-community/nix-ld).
