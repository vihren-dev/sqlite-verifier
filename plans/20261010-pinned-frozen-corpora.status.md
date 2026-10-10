# Pinned frozen corpora status

Created 2026-10-10. Status: IN PROGRESS (item 8; [PR #82](https://github.com/vihren-dev/sqlite-verifier/pull/82)).
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
- 2026-10-10: `conformance.progress.loaded_progress` reports progress for
  records that the caller loaded. The progress view test loads each corpus
  once. Local time of the v5 test: 64.6 s before, 33.3 s after.
- 2026-10-10: `conformance/pinned_corpora.py` pins v1 to v5 and the synthetic
  workload corpus by tree digest. `conformance.corpus.load` decodes a pinned
  corpus with `native_storage.decoded_record`; `validated_load` keeps the
  complete validation. `tests/conformance_pinned_corpora_test.py` (frozen
  suite) validates each pinned corpus completely, compares the fast path, and
  checks refusal of changed copies. The coverage test uses `loaded_progress`.
  Docs and the development replay task state the owner decision. Local
  sandboxed suites pass: frozen 161, model 56, sample 22, upstream 117,
  harness 129. Local frozen suite: 202 s (shared host).
- 2026-10-10: review findings fixed; `load_development_corpus` has a test of
  its pinned branch. Host source tests: 467 passed; 6 Lean compilation tests
  failed only while the Nix suites ran on the same shared host and pass when
  run alone (28 passed). Next: PR and hosted CI timings.
- 2026-10-10: PR #82 CI run 38078661914 passes on Linux. It reran the five
  conformance suites; the other five came from the cache. Linux times, before
  (run 37973585320) and after:
  - v5 progress view test: 102.5 s to 27.8 s; v4: 15.7 s to 8.3 s.
  - Sample CLI test: 87.5 s to 38.2 s.
  - v3 coverage test: 41.4 s to 14.2 s.
  - New pin test: v5 44.1 s, v3 11.6 s, v4 9.0 s.
  - `frozen` suite: 210.7 s to 152.2 s; `sample` suite: 96.7 s to 46.2 s.
  Unchanged model tests also changed by -3 % to -46 %, because fewer suites
  shared the runner. The task is DONE.
- 2026-10-10: owner request: move the pin test to its own `pinned` Nix suite.
  The pins move to `conformance/pinned-corpora.json`, which both Nix and
  `conformance/pinned_corpora.py` read. The suite inputs are the import
  closure of the validation (37 conformance modules and the SQL frontend),
  measured by running the complete validation of all pinned corpora.
  `tests/test_pinned_corpora_inventory.py` (host) checks that each
  `corpus-v*` directory is pinned.
