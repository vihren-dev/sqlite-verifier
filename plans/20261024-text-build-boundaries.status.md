# Status: translation dependencies and complete local law checks

Created 2026-10-24. Status: DONE. Implementation, required checks, and independent
reviews are complete.

Task: [task file](20261024-text-build-boundaries.task.md).
Specifications: [ADR 0016](../docs/adr-0016-model-and-surface.md), D2, and
[ADR 0020](../docs/adr-0020-local-build-loop.md).

## Current evidence

Base: PR #239, `srzmyvyu`, commit `98a07bfec142aacec28c0d3f9d4801dd593515f1`.
The task's relevant-file list names the code and existing checks.
`Translation/Located.lean` now imports the existing public root
`Belay.Sqlite.Model.Codec`. This root supplies syntax and restriction declarations
without the model umbrella. The layer check follows transitive imports from
`TranslationProgram`, with direct and indirect import regression cases.
The conformance lakefile defaults to `conformance-runner`; the Nix derivation and
the local `dev-build` recipe now explicitly build `VerifierConformance` and
`conformance-runner`.

Before the edit, `nix-build integrity/judge.nix -A predictions --out-link
build/predictions-before` produced 53 corpus files with 7,372 predictions at
`/nix/store/4k77z378vnagzwx5448yqz0686d58cld-sqlite-verifier-predictions`.
The post-edit output at
`/nix/store/w48z6q6q9byjjn620zg84rbxqmxyfcaw-sqlite-verifier-predictions`
is byte-identical across all 53 files. `just verdict` produced
`/nix/store/akcyn7ziqskq87mqw4g0alam40r23r3y-sqlite-verifier-verdict`:
4,838 AGREE, 2,534 MODEL_UNSUPPORTED, and no disagreements. Its prediction output
also matches all 53 baseline files byte-for-byte. All required gates passed.

## Acceptance

- `just test-full`: ten Nix suites, 792 tests, no failures, errors or skips.
  This includes 36 surface cases and 12 public-documentation cases. Report:
  `/nix/store/ykfdsmryx18cplw9zrf1dy3xakqlbydj-sqlite-verifier-test-reports`.
- `just verdict`: the Nix result and complete prediction comparison are above.
- `just test-nix`: 67 required Nix host checks passed. Report:
  `build/test-results/nix.xml`.
- `just test-scheduled-checks`: all 47 corpus-writer cases passed. Report:
  `/nix/store/wb3l2svhlw9hh0akzm6izc7rkwbqhx79-sqlite-verifier-scheduled-check-reports`.
  The owner instruction excludes broad local mutant runs; none were run.

Command logs are under `build/agent-logs/`: `test-full.log`, `verdict.log`,
`test-nix.log`, `test-scheduled-checks.log`, and `predictions-identical.log`.
No time or percentage improvement is claimed.

## Progress

- 2026-10-24: specified the import boundary and the missing local law-library
  check in response to the owner's modularity request. This workspace is
  separate from S4. Task review and implementation are pending.
- 2026-10-24: task review `20261024T115938Z-5fc56924` found no musts and two
  shoulds. The task now states the owner's scheduled-check override and the
  observed law-build failures from the handoff, and removes the proposed
  failure-injection harness. The existing local-loop test remains the check of
  the recipe. Implementation is pending.
- 2026-10-24: review `20261024T120211Z-4d34419d` found no musts and requested
  a durable record of the handoff evidence. The source is the owner-provided
  `/home/codex/work/HANDOFF-adr17-20261024.md`, section "How the work is done":
  "`just dev-build` builds only the conformance runner, not the law modules, and
  `test-full` failed twice because of this." This is a reported observation;
  that handoff supplies no run IDs, so this status does not claim independently
  verified failure logs. The task's target correction is independently supported
  by the current recipe and the Nix library targets recorded above.
  The same source, "Owner rules for this work", says: "Run only the relevant
  mutant tests, by name (`-k`). Never run `just test-scheduled` or
  `just test-mutants` locally; run `just test-scheduled-checks` at the end of a
  task." This is the owner instruction that overrides the older cadence table.
- 2026-10-24: narrowed the translator to the existing public codec root, added
  transitive-import checks to `tests/surface_layers_test.py`, and added the
  complete conformance library to `dev-build`. ADR 0020 lists the corrected
  targets and boundary. No model source, package root, semantic function, claim,
  or judge lock changed. Commit diagnostics use `tests/surface_layers_test.py`,
  `tests/dev_loop_test.py`, and `just dev-build`.
- 2026-10-24: implementation commit `7d9d7d06` received independent review
  `20261024T121422Z-7d9d7d06`: no must or should findings. All acceptance gates
  above passed after the code review. The task and status are DONE; the
  completion-record review and branch push follow this record.
- 2026-10-24: completion record `f223bd4b` received independent review
  `20261024T124107Z-f223bd4b`: no must or should findings. The branch for review is
  `tasks/text-build-boundaries`, based on `tasks/adr22-admitted-atoms` (PR #239).

## Local diagnostic procedure

The existing `tests/dev_loop_test.py` runs `just dev-build` twice and requires the
second run to compile no target. Inspect the initial build log for compilation of
`VerifierConformance.RunPassLaws`, which is outside the runner's import closure.

The proof-boundary diagnostic temporarily appends
`theorem Belay.Sqlite.Model.buildBoundaryProbe : True := True.intro` to
`packages/belay-sqlite-model/Belay/Sqlite/Model/QueryLaws.lean` and runs
`just dev-build`. Its assertions require recompilation of `QueryLaws` and the
model umbrella and no recompilation of Lean translation modules in the text
package's command. It records native targets separately. A `finally` block
restores the original source; another `just dev-build` checks the restored tree.
The timeout is 1,200 seconds per build. Logs are in
`build/agent-logs/proof-boundary-{build,restored,summary}.log`.
These local diagnostics do not supply semantic acceptance evidence.

## Separate observed issue: Python bytecode changes prediction inputs

This observation is outside this task's acceptance and changes no code here.
After the post-edit prediction build, the host source checks created two bytecode
files under `belay/sqlite/__pycache__`. `integrity/judge.nix` includes the whole
`belay` directory in `subjectSources`, so these files changed the prediction
derivation even though its Lean runtime stayed identical.

- Earlier prediction derivation:
  `/nix/store/jm12b3chq5j68jl0wk0dp0kk2ipszy9g-sqlite-verifier-predictions.drv`.
  Its Python source tree is
  `/nix/store/sv52zzb6krbiaa7jip7lcq02fwll5vjy-source`.
- Later prediction derivation, rebuilt by `just verdict`:
  `/nix/store/1h9sz1ldfqfm4xzvnsnqbwl94b6ip6hi-sqlite-verifier-predictions.drv`.
  Its Python source tree is
  `/nix/store/xa5ckc3gi8c8n0b58vx8adf1ipdrfjws-source`.
- `nix derivation show` reports the same runtime in both build commands:
  `/nix/store/6x07c4hgxnpf4qr4s0ahl4nlvxdcqa5p-sqlite-verifier-conformance`.
- `diff -qr` of those source trees reports only the two added files
  `belay/sqlite/__pycache__/profiles.cpython-314.pyc` and
  `belay/sqlite/__pycache__/quoted_text.cpython-314.pyc`.

The later prediction output is
`/nix/store/xc18hrcz7is34cb1naxz0yy4h9191x45-sqlite-verifier-predictions`.
The coordinator will specify the source-filter correction as a separate task.
