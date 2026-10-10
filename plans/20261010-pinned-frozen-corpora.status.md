# Pinned frozen corpora status

Created 2026-10-10. Status: IN PROGRESS.
Task: [20261010-pinned-frozen-corpora.task.md](20261010-pinned-frozen-corpora.task.md).

## References

- Loader: `conformance/corpus.py`, `conformance/corpus_shards.py`,
  `conformance/corpus_evidence.py`, `conformance/corpus_acquisition.py`,
  `conformance/native_storage.py`.
- Progress report: `conformance/progress.py`,
  `tests/conformance_progress_views_test.py`.
- Nix suites: `build-support/tests.nix`, `tests/nix_suites.json`.
- Design text: `docs/conformance-format-v2.md`,
  `plans/20261006-development-replay-headroom.task.md`.

## Baseline

CI run 37973585320 (main, 2026-10-09) ran the Nix suites; nightly run
38038004510 reused its results. Linux times:

- `frozen` suite: 210.7 s. The v5 progress view test: 102.5 s; the v4 test:
  15.7 s; `test_review_corpus_extends_and_replays`: 41.4 s.
- `sample` suite: 96.7 s. `test_frozen_cli_replays_every_authored_and_synthetic_case_within_bound`:
  87.5 s.

A local profile of `load(corpus-v5)` (shared host, times vary): about 28 s.
Shard decoding and checks take about 10 to 20 s; SHA-256 of all shard
payloads takes 0.24 s. Evidence validation takes about 7 s, of which the
historical Tcl binding scan takes 4.7 s. The scan tokenizes 176,237
commands; 4,867 are distinct, and 160,731 contain no `$`, `:` or `@`.

## Progress

- 2026-10-10: task and status files created.
- 2026-10-10: `named_slots` skips the tokenizer for a command without `$`,
  `:` or `@`. `tests/test_upstream_bindings.py` compares it with the
  tokenizer. A one-time check over all 5,033 distinct commands of corpora v1
  to v5 found no difference.
