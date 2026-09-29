# ADR 0003 latency experiments

Evidence for [ADR 0003](../../docs/adr-0003-agent-proof-preparation.md): where
current verification time goes, and what checking exported proof data costs.
Measured 2026-09-29 on one Apple Silicon Mac (`Darwin arm64`), warm file cache,
inside `nix develop path:./nix` after `just build`, at the repository revision
containing this directory. Linux was not measured. Numbers are medians of three
trials unless stated; they are one machine's observations, not guarantees.

## How to reproduce

```sh
python3 experiments/adr-0003-latency/stage_timing.py 3   # current source verify, per stage
experiments/adr-0003-latency/run_data_path.sh 3          # export + check strategies
```

`run_data_path.sh` compiles the examples with the production staged compiler
(`prepare_examples.py`), clones lean4export at tag `v4.33.0`
(`15f6055e299ad5b89345e533cc2192f4cc00f659`), applies
`lean4export-skip-trusted.patch`, builds the `bench` checker in `bench/`, and
writes everything under `build/adr-0003-latency/`. It needs network access for the
clone.

## Current path: `migration-check verify`

`stage_timing.py` wraps the verifier's process launcher in-process.

| Example | Total | Lean compile processes | Compile time | Kernel gate |
| --- | --- | --- | --- | --- |
| small positive (`add_column_then_table`) | 6.2 s | 7 | 3.7 s | 2.2 s |
| refutation (`missing_required_column`) | 6.2 s | 7 | 3.6 s | 2.2–2.4 s |
| Atuin | 19.5 s | 14 | 11.5–12.2 s | 6.4–7.2 s |

SQL parsing takes about 10 ms and dependency discovery 0.2–0.5 s. The first run
after a rebuild is slower (11.7–14.5 s for the small case) because of cold caches.

Fixed costs dominate the small cases:

| Lean process importing | Wall time |
| --- | --- |
| only `Init` (empty file) | 0.27 s |
| `SqliteVerifier` | 0.51 s |
| `Lean` and `SqliteVerifier` | 1.3 s |

Each compile process pays the 0.5 s `SqliteVerifier` import floor, whatever the
module contains. The gate imports `Lean` as part of its trusted base, costing
about 1.3 s before any replay.

## Data path: export with lean4export, then check

lean4export v4.33.0 builds and runs against the pinned Lean 4.33.0 unchanged.
Exports use the proof theorem plus the `VerificationConditions` inputs as roots.

| Example | Export, full closure | Export, library omitted |
| --- | --- | --- |
| small | 1.87 s, 27.0 MB, 5,106 declarations | 0.60 s, 11 KB, 12 declarations |
| refutation | 1.78 s, 25.2 MB, 4,726 declarations | 0.59 s, 15 KB, 12 declarations |
| Atuin | 1.93 s, 28.9 MB, 5,277 declarations | 0.67 s, 1.5 MB, 147 declarations |

"Library omitted" uses the experimental `--skip-trusted` patch: declarations from
`Init`, `Std`, `Lean` and `SqliteVerifier` are referenced by name but not emitted.

Checking strategies (`bench`, wall time including process start):

| Example | Full replay from empty environment | Trusted library + full export | Trusted library + library-omitted export |
| --- | --- | --- | --- |
| small | 5.50 s (parse 0.91, replay 4.5) | 1.49 s (parse 0.93) | 0.44 s |
| refutation | 4.99 s | 1.45 s | 0.44 s |
| Atuin | 7.26 s | 3.83 s | 2.55 s |

- *Full replay* is comparator's kernel step: every declaration, including the
  standard library, is re-checked.
- *Trusted library* imports the verifier-owned `SqliteVerifier` `.olean` closure
  (about 0.34 s), requires each exported declaration already present there to
  match, and replays only the rest.
- In the Atuin case, the 147 replayed declarations split into 114 contract and
  generated-input declarations (about 65 ms) and 33 candidate declarations
  (about 2.1 s, mostly `decide`-based proofs). Candidate proof checking is the
  irreducible part.

Exported declarations do not match their `.olean` form byte-for-byte: lean4export
removes metadata and sets every `let` nondep flag to false. After applying the
same normalization to the trusted side, all 5,094 (small) and 5,130 (Atuin)
repeated declarations matched as complete records.

## What this does not measure

- `bench` omits target reconstruction, the axiom audit and target comparison;
  today's gate performs them and they are expected to take milliseconds.
- Constructing the generated SQL/schema declarations inside the checker. Today
  they are two Lean compiles (about 1.0 s).
- Hostile-input decoding bounds, Nanoda, registry handling, and Linux.
- Agent-side incremental builds; only the export step of preparation is timed.

Comparator issue [#93](https://github.com/leanprover/comparator/issues/93)
reports that replay into an empty environment can reject proofs that reduce
string literals. The trusted-library strategy replays into an environment where
`Init` is already loaded; the Atuin export, which reduces strings, replayed
successfully that way.
