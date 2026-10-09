# ADR 0010: Compile verification workspaces with Lake and its artifact cache

Date: 2026-10-09. Status: PROPOSED.
Audience: designers and reviewers.
Related: [ADR 0002](adr-0002-compile-project-cache.md),
[ADR 0003](adr-0003-agent-proof-preparation.md),
[ADR 0003 trust extension](adr-0003-trust-extension.md),
[trust boundary](trust-boundary.md),
[latency experiment](../experiments/prepare-latency/README.md),
[Lake cache experiment](../experiments/lake-cache/README.md).

## Context

`prepare` and `verify-bundle` compile Lean modules themselves. For each module,
the verifier starts one `lean` process. It also runs `lean --deps-json` two
times for each module: once to discover sources and once more before each
compile. Modules compile one after another, also when they do not import each
other.

Each command starts with an empty temporary workspace. The opt-in stage store
(`MIGRATION_CHECK_STAGE_STORE`) can restore generated stages. ADR 0003 allows
reuse of an approved contract only for closures listed in
`cache_eligibility.py`, after a review of that closure. The list is empty. So
`verify-bundle` compiles the same approved contract again on every run, and CI
compiles the same example contracts again in every test.

Measured on Linux x86_64 (see the two experiments above). Compile and import
scan time only; export, checker and Python start do not change:

| Work | small | Atuin |
| --- | --- | --- |
| `prepare`, empty workspace, today | 2.35 s | 10.80 s |
| `prepare`, proof edit, today | 0.66 s | 1.13 s |
| `verify-bundle`, today | 1.08 s | 2.96 s |
| Lake, empty cache | 1.08 s | 4.89 s |
| Lake, proof edit, new directory | 0.38 s | 0.38 s |
| Lake, contract only, new directory, warm cache | 0.15 s | 0.18 s |

Lake, the Lean build tool, already does what the verifier needs:

- Each module has a key, its input hash. The key covers the source text, the
  keys and output hashes of the module's imports, the Lean toolchain, options,
  the module name and the package. The workspace path is not in the key.
- Lake keeps outputs in a shared artifact cache (`LAKE_CACHE_DIR`). A new
  workspace with the same sources compiles nothing.
- A changed module whose output does not change does not cause its importers to
  compile again. A comment added to `Requirements.lean` compiled only
  `Requirements`.
- Lake compiles independent modules in parallel and reads import headers itself.

The experiment also showed that the shipped runtime cannot be a Lake package
today. Its `lakefile.toml` requires `lean4export`, which the runtime does not
ship, and the runtime omits `.lake/build/ir`. Each Lake trace lists a `.c` file
there, so Lake decides that every `SqliteVerifier` module is not built.

## Decision

### 1. Lake compiles the verification workspace

`prepare` and `verify-bundle` write a workspace and run `lake build` in it. The
workspace contains:

- copies of the snapshotted approved, generated and (for `prepare` only)
  candidate sources;
- a `lean-toolchain` file with the pinned toolchain;
- a `lakefile.toml` that the verifier generates. It declares one library with
  the workspace modules as roots, enables the artifact cache, sets
  `restoreAllArtifacts = true`, and requires the runtime's library package by
  path.

The verifier never runs a `lakefile.lean` and never reads a lakefile from a
user. TOML is data; Lake does not execute it.

`verify-bundle` builds only the approved and generated modules. It never
compiles candidate source; this keeps the ADR 0003 rule that acceptance does not
accept candidate `.olean` files.

Source `verify` is out of scope. It keeps its current path until a separate
decision.

### 2. The verifier keeps its source rules

Lake does not know the roles of modules. Before Lake runs, the verifier checks
the import headers as today: approved modules must not import candidate or
reserved modules, and a candidate module must not have the name of an approved
or library module. The verifier reads all headers with one `lean --deps-json`
call for each discovery round, not one call for each module.

### 3. The runtime ships Lake library packages

The runtime build adds, for `SqliteVerifier` and `belaySqlite`:

- `.lake/build/ir` (about 200 KB for `SqliteVerifier`), so the shipped traces
  are complete;
- a library-only `lakefile.toml` without executables and without
  `lean4export`;
- `enableArtifactCache = false` in both library packages. Library outputs are
  read-only, and Lake must not copy them into the cache.

A test builds a generated workspace against the installed runtime and requires
that Lake compiles no library module.

### 4. One cache for each trust domain

A cache belongs to one **trust domain**: the set of processes that one entity
runs and protects. Any process that can write to a cache can put an output
into it that a later build uses without compiling. Lake's key is a 64-bit hash
that is not cryptographic; it detects accidental change, not attack. So a
cache is only as trusted as every process that can write to it.

- **Same entity runs `prepare` and `verify-bundle`.** Examples: a developer's
  machine, a CI job, an operator who runs the agent and the verifier under the
  same control. The two commands can use the same cache freely.
  `verify-bundle` then finds the contract that `prepare` compiled, and the
  reverse.
- **Separate environments.** In production, `verify-bundle` will probably run
  in a separate environment from `prepare`. `verify-bundle` then has its own
  cache, which only the verifier's processes can write. It never reads the
  agent's cache. Only the bundle crosses from the agent to the verifier. The
  verifier's cache still makes repeated checks fast: after the first run for a
  contract, it compiles nothing for that contract.

The cache location is a caller setting (`--cache DIR`, with a per-user default).
The caller protects it in the same way as the installation and the approved
sources; the [trust boundary](trust-boundary.md) adds the cache to that list.
A `--no-cache` option compiles everything with an empty, private cache.

### 5. Reuse of approved outputs replaces the eligibility registry

This decision replaces "Approved contract reuse" in ADR 0003 and the
eligibility policy of ADR 0002 §5.2 and §6.1. Reuse of an approved module's
output is allowed from a cache in the same trust domain. The per-closure review
and `cache_eligibility.py` are removed, together with `StageStore` and
`MIGRATION_CHECK_STAGE_STORE`.

Reuse is correct when compiling a module depends only on the inputs in its key.
Evidence: Lake rebuilt `SqliteVerifier.Contract` to a `.olean` that is
byte-identical to the shipped one. The remaining risk is approved Lean code that
reads state outside its key during elaboration: time, randomness, environment or
undeclared files. Lake makes the same assumption for every Lean project. People
review approved code, and such code is easy to see in a review. If the risk is
not acceptable for a contract, the caller uses `--no-cache`.

### 6. Process bounds

Today every `lean` process has its own deadline, output limit and minimal
environment. With Lake:

- `lake build` runs with one deadline for the whole build, a minimal
  environment (`PATH` to the pinned toolchain, `LAKE_CACHE_DIR`, `HOME` in the
  workspace) and bounded captured output;
- Lake's parallel jobs are limited to a configured number;
- the verifier maps Lake's failure output to the same per-module diagnostics as
  today.

### 7. Tests and CI: one seed for the whole run

Nix test targets are separate sandboxed derivations that run in parallel. They
cannot share one writable cache directory, and a shared directory would make a
target's result depend on the order of the targets. Instead, Nix builds the
cache once and gives a copy to each target:

- **Seed derivation.** A new Nix derivation generates the workspaces of the
  checked-in examples, runs `lake build -o mappings.jsonl` in each, and runs
  `lake cache stage` into its output. It compiles each example module once.
  The staged outputs are small: 40 KB for the small example, 188 KB for Atuin.
- **Test targets.** Only the targets that compile contracts (`atuin`,
  `bundle`, `cli`) take the seed as an input. At start, each target runs
  `lake cache unstage` into a writable cache in its `$TMPDIR` (inside a
  generated workspace, because Lake stores mappings for each package) and
  passes that cache to the verifier. A test that uses an example as it is
  compiles nothing. A test that changes its inputs compiles only the changed
  modules, and later tests in the same target reuse them.
- **Fixture environment.** Installed-runtime tests give each child a clean
  environment (`runtime_environment` in `conftest.py`). The cache setting is
  added there; a variable set on the derivation does not reach the verifier.
- **Keys do not contain paths.** Targets with different runtime roots
  (`runtime`, `leanRoot`, the conformance runtime) get hits when the library
  contents are the same. A difference causes misses, not wrong results.
- **Reruns.** The seed depends on the examples, the runtime and the Python
  code that generates `SchemaInputs`/`SqlInputs`. A change to one of them
  rebuilds the seed and runs the three targets again. They already run again
  on runtime and Python changes; only example changes add reruns. The seed adds
  about 6 s before these targets start.
- **Trust.** The seed is built in the Nix sandbox from repository sources, so
  it is in the CI job's trust domain (section 4). Only successful `main` jobs
  save the Nix cache, so a pull request cannot replace the seed that `main`
  uses.

A read-only cache is not used directly: with `enableArtifactCache = true` a
miss fails because Lake writes the new mapping, and with
`enableArtifactCache = false` Lake ignores the cache. The writable copy avoids
both problems.

A named set of tests runs with `--no-cache` and ignores the seed, so the path
without a cache stays tested. A test checks that a build from the cache and a
build without it give the same verification result. Host runs of
`just test-cases` use a persistent cache under `build/`.

### 8. The toolchain must report its commit

Lake puts the toolchain's commit hash into every key. A Lean built by Nix that
reports a release tag instead of the commit gets keys that never match: in
[ledger/ledger#3270](https://github.com/ledger/ledger/pull/3270), every CI run
compiled all of mathlib for this reason. Our pinned toolchain reports the
commit today. A test checks that `lean --version` reports the commit hash, so
a Lean upgrade cannot silently turn every cache hit into a miss.

## Consequences

- `prepare` and `verify-bundle` stop compiling unchanged modules. Expected
  acceptance time for Atuin: about 3.5 s instead of 6.6 s, most of it the
  bundle checker. Expected `prepare` time after a proof edit: under 1 s instead
  of about 2 s.
- The verifier no longer runs `lean --deps-json` before each compile.
- Lake becomes part of the trusted implementation. Its cache format and
  behavior can change with each Lean release, and the project follows each
  stable release (see "Lean maintenance" in [CLAUDE.md](../CLAUDE.md)). An
  upgrade must run the cache tests.
- Caches grow. The decision needs a size limit or a cleanup command.
- The trust milestone ([ADR 0003 trust extension](adr-0003-trust-extension.md))
  is compatible: hostile agents run `prepare` in their own trust domain, and
  `verify-bundle` keeps a cache that agents cannot write.

## Not yet verified

The experiment did not cover these. Each needs evidence before this ADR is
accepted:

- the exporter and the bundle checker reading Lake's outputs;
- mapping Lake failures to per-module diagnostics;
- macOS;
- cache growth over many contracts;
- the seed derivation inside the Nix sandbox (the `stage`/`unstage` flow was
  checked outside Nix with `experiments/lake-cache/seed_flow.py`).

## Alternatives considered

- **Keep the stage store and fix the orchestration** (the latency experiment's
  prototypes). Faster, but each command still compiles the contract unless the
  registry lists it. The registry needs a review of each user contract, which
  does not scale.
- **A per-module key in the stage store.** This copies Lake's design, without
  the cutoff on unchanged outputs, the parallel builds and Lake's maintenance.
- **A cache made by Nix for CI only.** It helps CI, not users.
- **A Lake and Nix integration** ([lean4-nix and lake2nix](https://github.com/lenianiva/lean4-nix),
  or `buildLakePackage` in nixpkgs). Both build one derivation for each
  package and let Lake reuse modules inside it; neither shares modules between
  our test targets, and both add a dependency that must follow every Lean
  release. Lean's own Nix support built one derivation for each module; it was
  removed before Lean 4.11. Users run `verify-bundle` without Nix, so Lake's
  cache is the mechanism in any case.
- **Lake's remote cache services** (Lean 4.30). They would share outputs
  across CI runs, but without signing and with a 64-bit key they are safe only
  inside one trust domain. The Nix cache, saved only from `main`, already
  does this.
- **Run Lake on the user's own project.** Rejected: a `lakefile.lean` is Lean
  code, and the verifier must not run it. The verifier also needs its own
  snapshot and role rules.
