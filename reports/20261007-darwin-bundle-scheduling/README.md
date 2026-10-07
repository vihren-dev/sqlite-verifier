# Darwin bundle scheduling evidence

The scheduling correction remains **IN PROGRESS**. Complete hosted acceptance
is required after publication. Earlier hosted failures remain failures.

| Observation | Result |
|---|---|
| Original PR47 `07dc71b3`, run `37486282958` | Darwin: 42 bundle cases passed in 324.20 s |
| Main `bc9e2dce`, run `37587787077` | Darwin: smaller 33-case bundle passed in 214.88 s |
| Main `b91e5cb5` and tag `v0.1.2` | Reused that exact cached 33-case output |
| PR47 `555b9a74`, run `37592057921` | Darwin bundle timed out at 420 s; Linux passed all 42 in 303.81 s |
| PR48 `8e10a593`, run `37592618106` | Darwin bundle timed out at 420 s; Linux passed all 42 in 334.95 s |
| One isolated exact PR47 build, session `38537` | Darwin: 42 passed, zero skips, in 235.46 s |

The retained original Darwin job logs are from jobs `112695903532` and
`112697693167`. Both show 20 completed cases and the first stage-reuse case
active when the whole bundle builder exited 124. Model builders were active.
The failures do not show an assertion failure or a separate model timeout.
Buffered hosted logs do not timestamp actual individual test starts.

## Isolated reproduction

The coordinator reserved the Darwin host and held other heavy jobs. The exact
failed derivation was
`/nix/store/bbqk4g8b9d3xa32qam8dk9d5ycw8gpxy-sqlite-verifier-test-bundle-1.drv`.
Its runtime was
`/nix/store/dsb751zkkicbqgxca8lkk3zf4rcz8i85-sqlite-verifier-runtime-1`.
The output did not exist, and Nix's validity query reported it invalid. The
normal build created
`/nix/store/86g0fw5iai8a1rs471hvvb00y2cpir5f-sqlite-verifier-test-bundle-1`.
No output was deleted, and `--check` was not used.

The unchanged builder ran the four original test files with `timeout 420`,
the same runtime and profiles, disabled automatic pytest plugins, and
`-p no:cacheprovider --junitxml "$out/junit.xml" -v --durations=10`.
The Nix invocation selected only that derivation, `--max-jobs 1`, explicit
sandboxing and disabled fallback. Its outer guard was 900 seconds. This
diagnostic setting does not change global CI parallelism.

Nix PID `94299` ran from `2026-10-07T08:43:39.247350+00:00` to
`2026-10-07T08:47:36.228967+00:00`. Monotonic nanoseconds were
`36807134561500` and `37044115990625`; the outer build took
236.981429125 seconds and exited 0. The original JUnit has 42 cases with no
failure, error or skip. The previously active stage-reuse case took 9.470
seconds including setup; its pytest call duration was 9.46 seconds.

Before and after manifests bind all 43 declared test-source files, 17,959
runtime files and 4,941 pytest interpreter files, plus the derivation and
observer/helper identities. They are equal. Full identity reads occurred
outside timing and can warm OS caches. Caches were preserved, their residency
was not observed, and this is not a cold-cache measurement.

Original streams, JUnit, boundaries, manifests, executed observer, derivation
and original twelve-file digest manifest are retained as gzip originals.
The metadata helper's exact bytes and both complete hosted failure logs are
also retained. `raw-sha256.json` binds all 16 original payloads and compressed
files. Stream events timestamp received complete lines, not pytest call
boundaries. The unchanged test fixture does not retain passing child-command
receipts; JUnit records per-node totals.

The isolated pass supports separating bundle from the concurrent complete
recipe. It does not prove that hosted contention caused the earlier misses,
and it does not replace complete hosted acceptance.

## Validation

The bounded validator checks raw bytes, exact command guards, before/after
identities, all JUnit outcomes and actual timing boundaries without a build:

```sh
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-darwin-bundle-scheduling/validate.py
```

Historical T03/T02 receipts, protected baselines and frozen corpus bytes are
unchanged. The task and status are in
[`plans`](../../plans/20261007-darwin-bundle-scheduling.task.md).
