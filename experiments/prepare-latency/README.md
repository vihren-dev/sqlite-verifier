# `prepare` and `verify-bundle` latency

Question: would `prepare` and `verify-bundle` be faster if they were a small
native binary instead of a Python package? This directory measures where their
wall time goes and how much four targeted changes save.

Measured 2026-10-09 on one Linux x86_64 host (8 CPUs, 62 GB RAM, warm file
cache), inside `nix develop path:./nix`, against the runtime from `just build`
at trunk `a6af0b31`. Numbers are medians: 5 trials for the baseline, 3 trials
for each prototype. They are one machine's observations.

## How to reproduce

```sh
nix develop path:./nix -c just build
nix develop path:./nix -c python3 experiments/prepare-latency/profile_data_path.py 5 > base.jsonl
nix develop path:./nix -c python3 experiments/prepare-latency/prototypes.py 3 wait,validate,header,parallel > all.jsonl
python3 experiments/prepare-latency/report.py base.jsonl all.jsonl
```

The scripts import the verifier from `build/runtime`, because the trunk `just
build` does not link `packages/belay-sqlite/.lake` into the checkout, so
`bin/migration-check` in the checkout stops with "Verifier runtime is
incomplete". The Python sources in `build/runtime/migration_check` are
identical to the checkout.

Scenarios, in order, on fresh copies of each example:

- `prepare_cold`: empty agent workspace.
- `prepare_noop`: the same inputs again.
- `prepare_proof_edit`: a comment appended to `Proofs.lean`.
- `verify_bundle`: no stage store.
- `verify_bundle_store_warm`: stage store filled by one earlier run, with the
  measurement-only approved-closure override.

## Result: a native rewrite would save little

Python interpreter start and imports take about 0.09 s per command
(`bin/migration-check prepare --help`). The rest of the time is child
processes and avoidable work in the orchestration. These changes are
equally possible in Python.

Baseline breakdown (seconds; process counts in parentheses):

| Case | Scenario | Total | Python | Lean compile | `--deps-json` | Export | Checker |
| --- | --- | --- | --- | --- | --- | --- | --- |
| small | prepare_cold | 3.20 | 0.37 | 1.56 (7) | 0.79 (12) | 0.42 | |
| small | prepare_proof_edit | 1.68 | 0.41 | 0.27 (1) | 0.39 (6) | 0.47 | |
| small | verify_bundle | 2.13 | 0.46 | 0.75 (3) | 0.33 (5) | | 0.52 |
| atuin | prepare_cold | 11.69 | 0.40 | 9.09 (14) | 1.71 (26) | 0.44 | |
| atuin | prepare_proof_edit | 1.96 | 0.32 | 0.27 (1) | 0.86 (13) | 0.44 | |
| atuin | verify_bundle | 6.62 | 0.32 | 2.11 (7) | 0.85 (13) | | 3.12 |
| atuin | verify_bundle_store_warm | 3.98 | 0.30 | 0 | 0.39 (6) | | 3.22 |

"Python" is wall time minus child-process time. Almost all of it is
`validate_libraries`, which globs every `.olean` under the Lean sysroot
(2,520 files) and both verifier libraries. It runs three times per command,
because `Runtime.locate` runs twice (once in `generated_inputs`, once in the
command) and `compile_contract` runs it again. Each scan takes 0.09 s.

## Findings

1. **Each module gets `lean --deps-json` twice.** `discover_sources` reads
   the imports of each module, and `lean_process` reads them again before
   each compile to build the search path. Each call costs 37–65 ms. This is
   the largest cost after the Lean compiles: 0.8–1.7 s for Atuin.
2. **`run_process` notices child exit late.** `Popen.wait(timeout=...)` polls
   with sleeps of up to 50 ms. A 37 ms `--deps-json` run takes 65 ms through
   `run_process`. A blocking wait with a kill timer keeps the same timeout.
3. **Import floor per compile is small on Linux.** A compile that imports
   `SqliteVerifier` takes 0.166 s; one that imports only `Init` takes 0.163 s.
   (The macOS figure in `../adr-0003-latency` is 0.5 s.) A long-lived Lean
   process that compiles many modules would save at most about 0.17 s per
   module.
4. **Candidate modules compile one by one.** In Atuin, `AtuinWitness`
   (2.4 s), `HistoryDecodingChecks` (2.2 s) and `AtuinFacts` (1.4 s) do not
   import each other.
5. **Fixed floors remain:** export 0.37–0.44 s, bundle checker 0.43–0.52 s
   (small) and 3.1 s (Atuin, mostly candidate `decide` proofs).

## Prototypes

`prototypes.py` applies each change as an in-process patch; it does not change
the verifier sources:

- `wait`: blocking wait with a kill timer instead of the polling wait.
- `validate`: scan the library trees once per process; call `Runtime.locate`
  once.
- `header`: read the `import` lines in Python instead of `lean --deps-json`.
  Before measuring, the script compares the result with Lean's on every
  example file. That check found the implicit `Init` import, which the first
  version omitted.
- `parallel`: in `prepare`, compile all candidate modules whose imports are
  ready at the same time.

Median total seconds. All 270 prototype runs gave the expected status
(PREPARED, VERIFIED, or VIOLATED for the refutation).

| Case | Scenario | Baseline | wait | validate | header | parallel | All four |
| --- | --- | --- | --- | --- | --- | --- | --- |
| small | prepare_cold | 3.20 | 2.54 | 2.79 | 2.29 | 3.11 | 1.60 |
| small | prepare_noop | 1.23 | 0.93 | 0.74 | 0.77 | 1.09 | 0.39 |
| small | prepare_proof_edit | 1.68 | 1.18 | 1.02 | 0.95 | 1.36 | 0.56 |
| small | verify_bundle | 2.13 | 1.62 | 1.46 | 1.42 | 1.80 | 0.95 |
| small | verify_bundle_store_warm | 1.14 | 0.87 | 0.60 | 0.82 | 0.95 | 0.43 |
| refutation | prepare_cold | 3.15 | 2.44 | 2.67 | 2.28 | 3.12 | 1.66 |
| refutation | prepare_proof_edit | 1.44 | 1.19 | 1.01 | 0.95 | 1.42 | 0.61 |
| refutation | verify_bundle | 1.86 | 1.50 | 1.42 | 1.47 | 1.75 | 0.96 |
| atuin | prepare_cold | 11.69 | 10.53 | 11.29 | 9.89 | 8.85 | 6.64 |
| atuin | prepare_noop | 1.61 | 1.25 | 1.26 | 0.83 | 1.61 | 0.46 |
| atuin | prepare_proof_edit | 1.96 | 1.49 | 1.57 | 1.02 | 1.89 | 0.67 |
| atuin | verify_bundle | 6.62 | 5.86 | 6.08 | 5.51 | 6.48 | 4.97 |
| atuin | verify_bundle_store_warm | 3.98 | 3.67 | 3.49 | 3.43 | 3.83 | 3.12 |

With all four, the Python share is 0.01–0.04 s. The remaining time is Lean
compiles, the export and the checker.

The "All four" column is slightly optimistic for one CLI call: the prototype
caches persist across the commands in one Python process. A real command would
still pay one library scan (0.09 s), one `lean --version` probe (0.035 s) and
interpreter start (0.09 s).

## Limits

- The `header` prototype is a regular expression. It does not handle every Lean
  header form (for example `module`, `public import`, block comments). It is
  acceptable only in `prepare`, which the verifier does not trust. In
  `verify-bundle`, the trusted side should keep Lean as the header parser.
  `lean --deps-json` accepts many files in one call: the 11 Atuin sources take
  0.04 s together. So the trusted side can read one discovery round per call
  and reuse those results for the compile step, instead of calling again per
  module.
- `parallel` was measured only in `prepare`. The approved-contract stage in
  `compile_contract` also compiles modules in sequence.
- Linux only; macOS process start and import costs are higher (see
  `../adr-0003-latency`).
Raw data: [results/](results/) (one JSON line per run).
