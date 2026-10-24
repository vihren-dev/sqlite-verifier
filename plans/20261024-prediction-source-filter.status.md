# Status: prediction source filter

Created 2026-10-24. Status: DONE. Required outcomes and checks passed.
Task: [task file](20261024-prediction-source-filter.task.md).
Relevant files: `integrity/judge.nix`, `tests/test_judge_lock.py`.

## Observed cost

The text-build-boundary agent reported this on 2026-10-24 while running its
Nix acceptance checks, after implementation commit `7d9d7d06`:

- Prediction derivation before Python bytecode appeared:
  `/nix/store/jm12b3chq5j68jl0wk0dp0kk2ipszy9g-sqlite-verifier-predictions.drv`.
  Its Python source tree: `/nix/store/sv52zzb6krbiaa7jip7lcq02fwll5vjy-source`.
- Derivation afterward, rebuilt by `just verdict`:
  `/nix/store/1h9sz1ldfqfm4xzvnsnqbwl94b6ip6hi-sqlite-verifier-predictions.drv`.
  Its Python source tree: `/nix/store/xa5ckc3gi8c8n0b58vx8adf1ipdrfjws-source`.
- Both used `/nix/store/6x07c4hgxnpf4qr4s0ahl4nlvxdcqa5p-sqlite-verifier-conformance`.
  The only source-tree differences were added
  `belay/sqlite/__pycache__/profiles.cpython-314.pyc` and
  `belay/sqlite/__pycache__/quoted_text.cpython-314.pyc`.

The coordinator inspected `subjectSources` and confirmed its unfiltered `belay`
input. These are the motivating observations, not acceptance of a fix.

## Progress

- 2026-10-24: specified the source-filter correction and a focused Nix identity
  regression. Implementation will be delegated after
  the current build-boundary task is complete, preserving its check boundary.
- 2026-10-24: review `20261024T122630Z-f6abffe7` found no musts and one should.
  The task now names the extra minimal Python inputs and fixed subject stub
  needed to evaluate predictions in the small identity fixture. It still uses
  the production judge expression and does not build the stub runtime.
- 2026-10-24: follow-up review `20261024T122820Z-7eb6003e` found no musts or
  shoulds. The specification is ready for delegation at the prior task boundary.
- 2026-10-24: carried task commit `3808f139` received independent review
  `20261024T124605Z-3808f139`, with no must or should findings, before implementation.
- 2026-10-24: applied the existing Python-file filter to both subject components.
  The focused `tests/test_judge_lock.py` fixture uses the production judge
  expression, minimal Python inputs, and a fixed runtime stub. It tests added,
  edited and removed bytecode plus source edits in both Python components.
  The bytecode regression failed against the original filter and all nine
  targeted Nix evaluation checks passed with the correction. Existing lock
  tamper checks remain in the same suite. No package or lock file changed.
- 2026-10-24: implementation commit `accfbf78` received independent review
  `20261024T125027Z-accfbf78`, with no must or should findings. All task-end
  checks passed.
- 2026-10-24: completion record review `20261024T125905Z-3d69f3e5` found no
  musts and one should about forward-looking progress text under the DONE
  header. Removed that sentence. No code or acceptance result changed.

## Acceptance evidence

All commands ran through `direnv exec .` with finite timeouts. Logs are under
`build/agent-logs/` in the `prediction-source-filter` workspace.

- `timeout 1800 nix-build integrity/judge.nix -A predictions` before and after
  the correction produced the same output:
  `/nix/store/164jh4a3m2xdajyfqwbbd1b1iilhgldf-sqlite-verifier-predictions`.
  All 53 prediction files, covering 7,372 cases, are byte-identical. Before the
  second build, importing `belay.sqlite.profiles` and `belay.sqlite.quoted_text`
  created their actual bytecode caches. The build reused the baseline output.
  The final identity evaluation after all task-end checks still produced
  `/nix/store/wi4cbnmcigh3slrldlpnvjcjr00in051-sqlite-verifier-predictions.drv`.
- `timeout 2400 just test-full` passed. Its unchanged Nix inputs reused
  `/nix/store/ykfdsmryx18cplw9zrf1dy3xakqlbydj-sqlite-verifier-test-reports`:
  792 tests across 10 suites, with no failures, errors or skips.
- `timeout 1900 just verdict` passed:
  `/nix/store/3qs9smjm4f6gsh9szippbhk3w668lxqd-sqlite-verifier-verdict`.
  The totals are 4,838 `AGREE` and 2,534 `MODEL_UNSUPPORTED`, with no disagreement
  or harness error. The claimed verdict rules are unchanged.
- `timeout 700 just test-nix` passed all 70 checks, including the new production
  prediction-identity checks and the existing lock-tamper checks.
- `timeout 2400 just test-scheduled-checks` passed. Its unchanged inputs reused
  `/nix/store/wb3l2svhlw9hh0akzm6izc7rkwbqhx79-sqlite-verifier-scheduled-check-reports`:
  47 writer tests, with no failures, errors or skips. The owner authorized this
  scheduled check target instead of the broad mutant suites.

`nix-instantiate --eval --strict --json integrity/judge.nix -A current` before
and after the correction produced equal values for all 55 locked parts, and
those values equal `integrity/judge.lock.json`. Outputs are recorded in
`build/agent-logs/lock-{before,after}.json` and `lock-unchanged.log`.
The command logs are `predictions-{before,after}.log`, `test-full.log`,
`verdict.log`, `test-nix.log` and `test-scheduled-checks.log`. The report summaries
and byte comparison are `full-report-summary.log`, `verdict-summary.log`,
`scheduled-report-summary.log` and `predictions-identical.log`.
