# ADR 0003 P1 results

Status: complete, 2026-09-29. macOS measured locally; Linux measured by workflow run
[36553342277](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36553342277)
on branch `adr3/p1-measure` (GitHub `ubuntu-22.04`, x86_64). Applied literally,
the [decision rule](../../docs/adr-0003-agent-proof-preparation.md) gives
**ship tuning** (details below).

## macOS summary (Apple Silicon, 5 warm trials + 1 cold per cell)

- **Correctness:** all 234 runs gave the expected status; the P1 attack cases are
  covered by `tests/bundle_test.py` and the existing kernel-gate and CLI suites.
- **No regressions:** neither option is slower than today's `verify` in any cell.
- **Tuning** cuts 27–55% for the small examples (6.3–7.0 s → 2.9–4.6 s) but only
  9–33% for Atuin (19.3–20.6 s → 13.7–18.1 s), whose time is mostly candidate
  compilation.
- **Data-path acceptance** is fast everywhere: 1.1–2.6 s for the small examples
  and 3.5–7.7 s for Atuin.
- **Data-path edit-to-result** against tuning, the decision rule's comparison:
  - Atuin proof edits: 48% (fresh contract) and 59% (reused) faster.
  - Atuin SQL edits: 2–4% faster. A SQL edit changes `SqlInputs`, so `prepare`
    recompiles every candidate module and loses the advantage.
  - Small and refutation proof edits: 3% slower to 9% faster.
  - Small SQL edits: 18–30% faster, flattered by the alternating SQL variants
    (see below).
  - Refutation SQL edits: 25–46% slower.
- **Contract edits** (not a required comparison): the data path's `prepare`
  rebuilds everything, so edit-to-result is slower than tuning for the small
  examples (5.8 s against 4.1–4.4 s) and similar for Atuin (17.1 s against 16.6 s).

## Linux summary

Linux repeats the macOS pattern at lower absolute times (today: 4.6–4.7 s for the
small examples, 15.6–15.8 s for Atuin):

- Correctness: all 234 runs gave the expected status.
- Data-path edit-to-result against tuning: Atuin proof edits 45% (fresh) and 55%
  (reused) faster; Atuin SQL edits 3–5% faster; small and refutation proof edits
  within ±4%; small SQL edits 16–17% faster; refutation SQL edits 29–38% slower.
- One data-path cell is slower than today: Atuin contract edit, edit-to-result
  15.86 s against 15.79 s (0.4%, within noise, but a regression under the rule).

## Outcome under the rule

**Ship tuning.** The data path is slower than tuning in required comparisons on
both platforms (refutation SQL edits, and small proof edits on macOS), so neither
"adopt" nor "owner decision" applies. The rule weights every example
equally, so the small examples, where both options already take a few seconds,
outweigh the large Atuin gain. Whether that weighting reflects the product goal is
an owner question; it is not changed here.

## Method notes

- "Today" ran from a checkout whose verifier sources are identical to the pre-P1
  revision (`6a670516`; `a8269f33` on the pushed branch).
- Each cell starts with fresh example copies, an empty stage store and an empty
  agent workspace. The cold trial does not drop operating-system file caches.
- "Reused" uses the measurement-only approved-closure override; no approved
  closure is registered as eligible.
- The small example's SQL edit alternates between its two valid statement orders,
  so its stored SQL stage is reused from the third trial on. The refutation and
  Atuin SQL edits are unique per trial.
- Raw data: [results/Darwin-arm64.jsonl](results/Darwin-arm64.jsonl).

## Generated report

Warm medians; cold first trial in parentheses.

| Platform | Example | Change | Option | Contract | Acceptance s | Edit to result s |
| --- | --- | --- | --- | --- | --- | --- |
| Darwin | atuin | contract | today | fresh | 19.66 (23.91) | 19.66 (23.91) |
| Darwin | atuin | contract | tuning | fresh | 16.63 (18.97) | 16.63 (18.97) |
| Darwin | atuin | contract | data | fresh | 6.10 (7.22) | 17.09 (19.13) |
| Darwin | atuin | proof | today | fresh | 20.61 (23.50) | 20.61 (23.50) |
| Darwin | atuin | proof | tuning | fresh | 18.06 (19.38) | 18.06 (19.38) |
| Darwin | atuin | proof | tuning | reused | 13.74 (18.88) | 13.74 (18.88) |
| Darwin | atuin | proof | data | fresh | 7.24 (8.32) | 9.34 (22.59) |
| Darwin | atuin | proof | data | reused | 3.52 (8.57) | 5.66 (22.68) |
| Darwin | atuin | sql | today | fresh | 19.33 (22.81) | 19.33 (22.81) |
| Darwin | atuin | sql | tuning | fresh | 17.61 (17.72) | 17.61 (17.72) |
| Darwin | atuin | sql | tuning | reused | 14.39 (19.62) | 14.39 (19.62) |
| Darwin | atuin | sql | data | fresh | 7.70 (8.13) | 17.33 (22.10) |
| Darwin | atuin | sql | data | reused | 4.14 (8.33) | 13.87 (21.80) |
| Darwin | refutation | contract | today | fresh | 6.58 (9.77) | 6.58 (9.77) |
| Darwin | refutation | contract | tuning | fresh | 4.07 (5.36) | 4.07 (5.36) |
| Darwin | refutation | contract | data | fresh | 2.15 (3.23) | 5.79 (8.37) |
| Darwin | refutation | proof | today | fresh | 6.29 (9.76) | 6.29 (9.76) |
| Darwin | refutation | proof | tuning | fresh | 3.91 (5.17) | 3.91 (5.17) |
| Darwin | refutation | proof | tuning | reused | 2.87 (4.96) | 2.87 (4.96) |
| Darwin | refutation | proof | data | fresh | 2.10 (3.37) | 3.66 (8.22) |
| Darwin | refutation | proof | data | reused | 1.07 (3.29) | 2.62 (8.25) |
| Darwin | refutation | sql | today | fresh | 6.30 (9.27) | 6.30 (9.27) |
| Darwin | refutation | sql | tuning | fresh | 4.57 (5.19) | 4.57 (5.19) |
| Darwin | refutation | sql | tuning | reused | 3.40 (5.03) | 3.40 (5.03) |
| Darwin | refutation | sql | data | fresh | 2.60 (3.19) | 5.71 (8.00) |
| Darwin | refutation | sql | data | reused | 1.59 (3.13) | 4.99 (7.69) |
| Darwin | small | contract | today | fresh | 6.37 (6.78) | 6.37 (6.78) |
| Darwin | small | contract | tuning | fresh | 4.42 (5.27) | 4.42 (5.27) |
| Darwin | small | contract | data | fresh | 2.15 (3.51) | 5.80 (8.83) |
| Darwin | small | proof | today | fresh | 6.35 (13.83) | 6.35 (13.83) |
| Darwin | small | proof | tuning | fresh | 4.03 (5.15) | 4.03 (5.15) |
| Darwin | small | proof | tuning | reused | 2.96 (6.02) | 2.96 (6.02) |
| Darwin | small | proof | data | fresh | 2.21 (3.52) | 4.16 (9.50) |
| Darwin | small | proof | data | reused | 1.09 (3.25) | 2.75 (7.96) |
| Darwin | small | sql | today | fresh | 7.00 (10.48) | 7.00 (10.48) |
| Darwin | small | sql | tuning | fresh | 4.21 (5.49) | 4.21 (5.49) |
| Darwin | small | sql | tuning | reused | 3.21 (5.01) | 3.21 (5.01) |
| Darwin | small | sql | data | fresh | 2.22 (3.32) | 3.45 (8.62) |
| Darwin | small | sql | data | reused | 1.17 (3.21) | 2.23 (8.52) |
| Linux | atuin | contract | today | fresh | 15.79 (15.89) | 15.79 (15.89) |
| Linux | atuin | contract | tuning | fresh | 14.80 (15.13) | 14.80 (15.13) |
| Linux | atuin | contract | data | fresh | 5.88 (6.52) | 15.86 (17.60) |
| Linux | atuin | proof | today | fresh | 15.74 (15.64) | 15.74 (15.64) |
| Linux | atuin | proof | tuning | fresh | 13.86 (14.62) | 13.86 (14.62) |
| Linux | atuin | proof | tuning | reused | 11.24 (14.53) | 11.24 (14.53) |
| Linux | atuin | proof | data | fresh | 5.78 (6.47) | 7.65 (17.02) |
| Linux | atuin | proof | data | reused | 3.18 (6.47) | 5.05 (17.04) |
| Linux | atuin | sql | today | fresh | 15.58 (15.63) | 15.58 (15.63) |
| Linux | atuin | sql | tuning | fresh | 14.36 (14.88) | 14.36 (14.88) |
| Linux | atuin | sql | tuning | reused | 11.75 (14.98) | 11.75 (14.98) |
| Linux | atuin | sql | data | fresh | 6.05 (6.46) | 13.68 (17.02) |
| Linux | atuin | sql | data | reused | 3.60 (6.67) | 11.44 (17.54) |
| Linux | refutation | contract | today | fresh | 4.73 (4.58) | 4.73 (4.58) |
| Linux | refutation | contract | tuning | fresh | 3.08 (3.77) | 3.08 (3.77) |
| Linux | refutation | contract | data | fresh | 1.64 (2.37) | 4.35 (5.91) |
| Linux | refutation | proof | today | fresh | 4.58 (4.53) | 4.58 (4.53) |
| Linux | refutation | proof | tuning | fresh | 3.04 (3.63) | 3.04 (3.63) |
| Linux | refutation | proof | tuning | reused | 2.39 (3.87) | 2.39 (3.87) |
| Linux | refutation | proof | data | fresh | 1.68 (2.42) | 3.02 (5.86) |
| Linux | refutation | proof | data | reused | 0.95 (2.37) | 2.29 (5.86) |
| Linux | refutation | sql | today | fresh | 4.73 (4.73) | 4.73 (4.73) |
| Linux | refutation | sql | tuning | fresh | 3.45 (3.82) | 3.45 (3.82) |
| Linux | refutation | sql | tuning | reused | 2.71 (3.82) | 2.71 (3.82) |
| Linux | refutation | sql | data | fresh | 2.01 (2.32) | 4.44 (5.88) |
| Linux | refutation | sql | data | reused | 1.31 (2.37) | 3.75 (5.65) |
| Linux | small | contract | today | fresh | 4.58 (4.58) | 4.58 (4.58) |
| Linux | small | contract | tuning | fresh | 2.93 (3.72) | 2.93 (3.72) |
| Linux | small | contract | data | fresh | 1.58 (2.37) | 4.28 (5.81) |
| Linux | small | proof | today | fresh | 4.55 (4.50) | 4.55 (4.50) |
| Linux | small | proof | tuning | fresh | 2.93 (3.78) | 2.93 (3.78) |
| Linux | small | proof | tuning | reused | 2.25 (3.56) | 2.25 (3.56) |
| Linux | small | proof | data | fresh | 1.58 (2.27) | 2.91 (5.66) |
| Linux | small | proof | data | reused | 0.95 (2.42) | 2.28 (5.75) |
| Linux | small | sql | today | fresh | 4.58 (4.53) | 4.58 (4.53) |
| Linux | small | sql | tuning | fresh | 3.03 (3.67) | 3.03 (3.67) |
| Linux | small | sql | tuning | reused | 2.30 (3.72) | 2.30 (3.72) |
| Linux | small | sql | data | fresh | 1.59 (2.27) | 2.55 (5.60) |
| Linux | small | sql | data | reused | 0.95 (2.37) | 1.92 (5.72) |

## Decision rule

- Correctness: tuning passes, data path passes (0 wrong statuses).
- Regressions against today: {"tuning": [], "data": ["Linux/atuin/contract/fresh/edit_to_result_s"]}
- Data-path edit-to-result improvement over tuning: Darwin/atuin/proof/fresh +48%, Darwin/atuin/proof/reused +59%, Darwin/atuin/sql/fresh +2%, Darwin/atuin/sql/reused +4%, Darwin/refutation/proof/fresh +6%, Darwin/refutation/proof/reused +9%, Darwin/refutation/sql/fresh -25%, Darwin/refutation/sql/reused -46%, Darwin/small/proof/fresh -3%, Darwin/small/proof/reused +7%, Darwin/small/sql/fresh +18%, Darwin/small/sql/reused +30%, Linux/atuin/proof/fresh +45%, Linux/atuin/proof/reused +55%, Linux/atuin/sql/fresh +5%, Linux/atuin/sql/reused +3%, Linux/refutation/proof/fresh +1%, Linux/refutation/proof/reused +4%, Linux/refutation/sql/fresh -29%, Linux/refutation/sql/reused -38%, Linux/small/proof/fresh +1%, Linux/small/proof/reused -1%, Linux/small/sql/fresh +16%, Linux/small/sql/reused +17%
- Outcome: SHIP TUNING.
