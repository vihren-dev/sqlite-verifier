# Lake artifact cache for `prepare` and `verify-bundle`

Question: can the verifier let Lake compile its generated workspaces, so that
Lake's artifact cache supplies every `.olean` that was compiled before, in
`prepare` and in `verify-bundle`?

Measured 2026-10-09 on one Linux x86_64 host (8 CPUs), Lean and Lake 4.34.1
(Lake 5.0.0), runtime from `just build` at trunk `a6af0b31`. Medians of 3 trials.

## How to reproduce

```sh
nix develop path:./nix -c just build
nix develop path:./nix -c python3 experiments/lake-cache/setup_shim.py build/lake-cache
nix develop path:./nix -c python3 experiments/lake-cache/lake_bench.py build/lake-cache 3
nix develop path:./nix -c python3 experiments/lake-cache/seed_flow.py build/lake-cache
```

`lake_bench.py` writes one TOML-only workspace per scenario, in a new directory:
a `lakefile.toml` (data, not Lean code) with one library whose roots are the
approved, generated and candidate modules, plus copies of those sources. The
workspace sets `enableArtifactCache = true` and `restoreAllArtifacts = true` and
requires the `sqliteVerifier` package from `setup_shim.py`.

## Results

| Scenario | small | Atuin | Compiled modules |
| --- | --- | --- | --- |
| Empty cache, all modules | 1.08 s | 4.89 s | 7 / 14 |
| New directory, same sources | 0.18 s | 0.18 s | 0 |
| New directory, `Proofs.lean` edited | 0.38 s | 0.38 s | 1 |
| New directory, contract and generated modules only | 0.15 s | 0.18 s | 0 |
| Same directory again (no-op) | 0.15 s | 0.17 s | 0 |

The same work today (compiles plus `lean --deps-json`, from
`../prepare-latency/README.md`):

| Today | small | Atuin |
| --- | --- | --- |
| `prepare`, empty workspace | 2.35 s | 10.80 s |
| `prepare`, proof edit | 0.66 s | 1.13 s |
| `verify-bundle`, no store | 1.08 s | 2.96 s |

Export (0.4 s), the bundle checker (0.4 s / 3.1 s) and Python orchestration are
outside these tables and do not change.

## Findings

1. **Reuse works across directories.** A new workspace with the same sources
   compiles nothing. The key does not depend on the workspace path.
2. **Only changed output propagates.** A comment added to `Requirements.lean`
   rebuilt `Requirements` only: its `.olean` did not change, so the modules
   that import it came from the cache. The key of a module includes the hashes
   of its imports' outputs.
3. **Lake compiles in parallel and reads headers itself.** No `lean --deps-json`
   processes; Atuin's independent modules build at the same time.
4. **The shipped runtime is not usable as a Lake package as is:**
   - Its `lakefile.toml` requires `lean4export`, which the runtime does not
     ship. The shim uses a library-only lakefile instead.
   - It omits `.lake/build/ir`. Each module trace lists a `.c` output there, so
     Lake treats every `SqliteVerifier` module as not built and tries to
     rebuild it in the read-only Nix store. Belay ships `ir` and works. The
     missing files are 204 KB.
   - Library packages must set `enableArtifactCache = false`. Otherwise Lake
     copies their read-only outputs into the cache and fails.
5. **Compilation is reproducible here.** Lake rebuilt `SqliteVerifier.Contract`
   to a `.olean` byte-identical to the shipped one, with the same trace hash.
6. **A cache on another filesystem works.** With the cache under `/home` and
   the workspace in `/tmp`, Lake copied instead of hard-linking, at the same speed.
7. **Generated `lean-toolchain`.** Without one, Lake writes it and stops with
   "you will need to manually restart Lake". The workspace must include it.
8. **A read-only cache works only for reading.** With a read-only cache
   directory:
   - `enableArtifactCache = true`: hits work; a miss fails with "permission
     denied", because Lake writes the new mapping.
   - `enableArtifactCache = false`: Lake ignores the cache and compiles all
     modules.
   - setting absent: hits work, and a miss compiles locally without writing
     (a proof edit compiled 1 module).
9. **A seed moves between caches with `stage` and `unstage`.** `lake build -o
   mappings.jsonl` records the outputs of the root package; `lake cache stage`
   copies them to a directory (40 KB small, 188 KB Atuin); `lake cache unstage`,
   run inside a generated workspace, copies them into another cache. On that
   cache, new workspaces for both examples compiled nothing, and a proof edit
   compiled only `Proofs` (`seed_flow.py`).
10. **The cache key contains the toolchain's commit hash.** The traces record
    "Lean 4.34.1, commit 5045d00…". A Lean built by Nix that reports a tag
    instead of the commit gets different keys and no cache hits (see
    [ledger/ledger#3270](https://github.com/ledger/ledger/pull/3270)). Ours
    reports the commit.

## Not covered

- The exporter and the bundle checker were not run on Lake's output. They need
  the workspace's `.lake/build/lib/lean` on their search path.
- Error reporting: today each compile failure becomes a `CompileError` for one
  module. Lake reports failures in its own output format.
- Process bounds: today every `lean` process has its own deadline, output limit
  and minimal environment. Lake starts `lean` itself.
- Cache growth and cleanup, and macOS.
