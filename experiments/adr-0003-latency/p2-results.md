# ADR 0003 P2 re-measurement

Status: complete, 2026-09-29. Same harness and matrix as
[P1](p1-results.md) (5 warm trials + 1 cold per cell, 234 runs per platform, all
with the expected status), after P2 made `prepare` rebuild only modules whose
imports changed. macOS ran locally at `ad1c901d`; Linux ran in workflow run
[36570573314](https://github.com/vihren-dev/sqlite-verifier/actions/runs/36570573314)
on branch `adr3/p2-measure` (`5a054e44`, the same code plus a temporary trigger).
"Today" is `main` before ADR 0003 (`914c9c29`). Compare options within a run:
absolute times differ from P1 because host load and runners differ.

## What changed since P1

Data-path edit-to-result time against tuning (fresh contract / reused contract):

| Example and edit | P1 macOS | P2 macOS | P1 Linux | P2 Linux |
| --- | --- | --- | --- | --- |
| Atuin, proof edit | +48% / +59% | +47% / +59% | +45% / +55% | +54% / +62% |
| **Atuin, SQL edit** | +2% / +4% | **+27% / +32%** | +5% / +3% | **+36% / +38%** |
| small, proof edit | −3% / +7% | +7% / +11% | +1% / −1% | +2% / 0% |
| small, SQL edit | +18% / +30% | +22% / +30% | +16% / +17% | +10% / +16% |
| refutation, proof edit | +6% / +9% | +6% / +11% | +1% / +4% | +7% / +3% |
| refutation, SQL edit | −25% / −46% | −28% / −35% | −29% / −38% | −36% / −32% |

Atuin's `AtuinWitness` and `HistoryDecodingChecks` do not import the generated SQL
inputs, so a SQL edit now reuses them instead of recompiling about 4.5 s of work.

## P2 exit criteria

- **SQL edits against tuning, with any gap explained.** Atuin SQL edits are now
  27–38% faster than tuning. Small SQL edits are 10–30% faster. Refutation SQL
  edits remain 28–36% slower: every candidate module in that example imports the
  generated SQL inputs, so dependency-aware preparation has nothing to skip, and
  the data path still pays for compiling `SqlInputs` twice (in `prepare` and in
  `verify-bundle`) plus the 0.6 s export. P3 (direct construction of the generated
  inputs) removes the verifier's compile; the export cost remains for proofs this
  small, where both options take 3–5 s.
- **No data-path cell slower than today's `verify` beyond noise.** Linux: none.
  macOS: the Atuin contract edit's median is 16.96 s against 16.93 s (0.2%); warm
  trials span 16.59–17.84 s against 16.80–17.90 s, so the difference is noise.
- **Correctness:** 468 runs with the expected status; bundle and installed
  acceptance suites pass (installed on aarch64-darwin; Linux installed acceptance
  runs in PR CI).

The literal P1 rule would still say "ship tuning" because refutation SQL edits are
slower; the owner decision in ADR 0003 already covers that case.

Raw data: [results/p2/](results/p2/Darwin-arm64.jsonl) (macOS and Linux JSON lines).

Warm medians; cold first trial in parentheses.

| Platform | Example | Change | Option | Contract | Acceptance s | Edit to result s |
| --- | --- | --- | --- | --- | --- | --- |
| Darwin | atuin | contract | today | fresh | 16.93 (18.30) | 16.93 (18.30) |
| Darwin | atuin | contract | tuning | fresh | 14.42 (15.80) | 14.42 (15.80) |
| Darwin | atuin | contract | data | fresh | 6.16 (7.05) | 16.96 (18.96) |
| Darwin | atuin | proof | today | fresh | 16.52 (16.90) | 16.52 (16.90) |
| Darwin | atuin | proof | tuning | fresh | 14.50 (15.58) | 14.50 (15.58) |
| Darwin | atuin | proof | tuning | reused | 11.50 (15.37) | 11.50 (15.37) |
| Darwin | atuin | proof | data | fresh | 6.00 (7.07) | 7.74 (18.79) |
| Darwin | atuin | proof | data | reused | 2.99 (6.96) | 4.72 (18.46) |
| Darwin | atuin | sql | today | fresh | 16.38 (16.83) | 16.38 (16.83) |
| Darwin | atuin | sql | tuning | fresh | 15.27 (16.77) | 15.27 (16.77) |
| Darwin | atuin | sql | tuning | reused | 12.09 (15.63) | 12.09 (15.63) |
| Darwin | atuin | sql | data | fresh | 6.72 (7.40) | 11.17 (19.60) |
| Darwin | atuin | sql | data | reused | 3.58 (7.68) | 8.20 (19.50) |
| Darwin | refutation | contract | today | fresh | 5.44 (8.97) | 5.44 (8.97) |
| Darwin | refutation | contract | tuning | fresh | 3.43 (4.49) | 3.43 (4.49) |
| Darwin | refutation | contract | data | fresh | 1.84 (2.86) | 4.92 (7.11) |
| Darwin | refutation | proof | today | fresh | 5.36 (8.52) | 5.36 (8.52) |
| Darwin | refutation | proof | tuning | fresh | 3.35 (4.42) | 3.35 (4.42) |
| Darwin | refutation | proof | tuning | reused | 2.53 (4.34) | 2.53 (4.34) |
| Darwin | refutation | proof | data | fresh | 1.84 (2.84) | 3.14 (7.09) |
| Darwin | refutation | proof | data | reused | 0.95 (2.76) | 2.26 (6.74) |
| Darwin | refutation | sql | today | fresh | 5.53 (8.54) | 5.53 (8.54) |
| Darwin | refutation | sql | tuning | fresh | 3.87 (4.55) | 3.87 (4.55) |
| Darwin | refutation | sql | tuning | reused | 3.00 (4.39) | 3.00 (4.39) |
| Darwin | refutation | sql | data | fresh | 2.30 (2.85) | 4.94 (7.13) |
| Darwin | refutation | sql | data | reused | 1.39 (2.75) | 4.03 (6.73) |
| Darwin | small | contract | today | fresh | 5.35 (7.83) | 5.35 (7.83) |
| Darwin | small | contract | tuning | fresh | 3.37 (4.39) | 3.37 (4.39) |
| Darwin | small | contract | data | fresh | 1.79 (2.86) | 4.87 (7.12) |
| Darwin | small | proof | today | fresh | 5.35 (5.78) | 5.35 (5.78) |
| Darwin | small | proof | tuning | fresh | 3.38 (4.53) | 3.38 (4.53) |
| Darwin | small | proof | tuning | reused | 2.45 (4.27) | 2.45 (4.27) |
| Darwin | small | proof | data | fresh | 1.86 (2.84) | 3.16 (7.12) |
| Darwin | small | proof | data | reused | 0.89 (2.70) | 2.17 (6.66) |
| Darwin | small | sql | today | fresh | 5.38 (9.20) | 5.38 (9.20) |
| Darwin | small | sql | tuning | fresh | 3.38 (4.43) | 3.38 (4.43) |
| Darwin | small | sql | tuning | reused | 2.46 (4.26) | 2.46 (4.26) |
| Darwin | small | sql | data | fresh | 1.80 (2.86) | 2.63 (7.18) |
| Darwin | small | sql | data | reused | 0.90 (2.70) | 1.73 (6.72) |
| Linux | atuin | contract | today | fresh | 11.92 (11.69) | 11.92 (11.69) |
| Linux | atuin | contract | tuning | fresh | 10.79 (11.01) | 10.79 (11.01) |
| Linux | atuin | contract | data | fresh | 4.24 (4.51) | 11.37 (11.99) |
| Linux | atuin | proof | today | fresh | 13.35 (13.14) | 13.35 (13.14) |
| Linux | atuin | proof | tuning | fresh | 12.77 (12.71) | 12.77 (12.71) |
| Linux | atuin | proof | tuning | reused | 10.60 (13.53) | 10.60 (13.53) |
| Linux | atuin | proof | data | fresh | 4.75 (5.30) | 5.94 (14.01) |
| Linux | atuin | proof | data | reused | 2.79 (5.26) | 3.99 (14.00) |
| Linux | atuin | sql | today | fresh | 13.42 (13.45) | 13.42 (13.45) |
| Linux | atuin | sql | tuning | fresh | 11.11 (11.80) | 11.11 (11.80) |
| Linux | atuin | sql | tuning | reused | 8.90 (10.59) | 8.90 (10.59) |
| Linux | atuin | sql | data | fresh | 4.37 (4.64) | 7.11 (12.08) |
| Linux | atuin | sql | data | reused | 2.75 (4.77) | 5.49 (12.47) |
| Linux | refutation | contract | today | fresh | 3.36 (3.78) | 3.36 (3.78) |
| Linux | refutation | contract | tuning | fresh | 2.08 (2.86) | 2.08 (2.86) |
| Linux | refutation | contract | data | fresh | 1.13 (1.56) | 3.01 (3.71) |
| Linux | refutation | proof | today | fresh | 3.26 (3.12) | 3.26 (3.12) |
| Linux | refutation | proof | tuning | fresh | 2.15 (2.48) | 2.15 (2.48) |
| Linux | refutation | proof | tuning | reused | 1.68 (2.60) | 1.68 (2.60) |
| Linux | refutation | proof | data | fresh | 1.12 (1.58) | 1.99 (3.74) |
| Linux | refutation | proof | data | reused | 0.69 (1.55) | 1.62 (3.95) |
| Linux | refutation | sql | today | fresh | 3.23 (3.26) | 3.23 (3.26) |
| Linux | refutation | sql | tuning | fresh | 2.34 (2.60) | 2.34 (2.60) |
| Linux | refutation | sql | tuning | reused | 2.09 (2.54) | 2.09 (2.54) |
| Linux | refutation | sql | data | fresh | 1.55 (1.65) | 3.19 (3.89) |
| Linux | refutation | sql | data | reused | 1.07 (1.81) | 2.77 (4.28) |
| Linux | small | contract | today | fresh | 3.16 (3.12) | 3.16 (3.12) |
| Linux | small | contract | tuning | fresh | 1.92 (2.45) | 1.92 (2.45) |
| Linux | small | contract | data | fresh | 1.07 (1.50) | 2.75 (3.58) |
| Linux | small | proof | today | fresh | 3.07 (3.12) | 3.07 (3.12) |
| Linux | small | proof | tuning | fresh | 1.94 (2.47) | 1.94 (2.47) |
| Linux | small | proof | tuning | reused | 1.49 (2.35) | 1.49 (2.35) |
| Linux | small | proof | data | fresh | 1.08 (1.51) | 1.89 (3.78) |
| Linux | small | proof | data | reused | 0.69 (1.50) | 1.49 (3.59) |
| Linux | small | sql | today | fresh | 3.12 (3.13) | 3.12 (3.13) |
| Linux | small | sql | tuning | fresh | 1.97 (2.55) | 1.97 (2.55) |
| Linux | small | sql | tuning | reused | 1.57 (2.41) | 1.57 (2.41) |
| Linux | small | sql | data | fresh | 1.16 (1.55) | 1.77 (3.67) |
| Linux | small | sql | data | reused | 0.69 (1.56) | 1.32 (3.64) |

## Rule check (P1 rule, for reference)

- Correctness: tuning passes, data path passes (0 wrong statuses).
- Regressions against today: {"tuning": [], "data": ["Darwin/atuin/contract/fresh/edit_to_result_s"]}
- Data-path edit-to-result improvement over tuning: Darwin/atuin/proof/fresh +47%, Darwin/atuin/proof/reused +59%, Darwin/atuin/sql/fresh +27%, Darwin/atuin/sql/reused +32%, Darwin/refutation/proof/fresh +6%, Darwin/refutation/proof/reused +11%, Darwin/refutation/sql/fresh -28%, Darwin/refutation/sql/reused -35%, Darwin/small/proof/fresh +7%, Darwin/small/proof/reused +11%, Darwin/small/sql/fresh +22%, Darwin/small/sql/reused +30%, Linux/atuin/proof/fresh +54%, Linux/atuin/proof/reused +62%, Linux/atuin/sql/fresh +36%, Linux/atuin/sql/reused +38%, Linux/refutation/proof/fresh +7%, Linux/refutation/proof/reused +3%, Linux/refutation/sql/fresh -36%, Linux/refutation/sql/reused -32%, Linux/small/proof/fresh +2%, Linux/small/proof/reused -0%, Linux/small/sql/fresh +10%, Linux/small/sql/reused +16%
- Outcome: SHIP TUNING.
