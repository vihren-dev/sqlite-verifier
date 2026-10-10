# Validate frozen corpora once and pin their bytes

Created 2026-10-10. Status: DONE ([PR #82](https://github.com/vihren-dev/sqlite-verifier/pull/82)).
Owner request: CI spends most of the time of the slowest frozen tests in
`conformance.corpus.load`, which validates the same unchanged corpus again
in each call. Validate each frozen corpus once; later loads check only that
the bytes are the validated bytes.

## Outcome

1. The repository pins each checked-in frozen corpus (v1 to v5 and the
   synthetic workload corpus) by one digest of its complete directory tree:
   each regular file's relative path and SHA-256 digest.
2. `conformance.corpus.load` computes the tree digest of the requested
   directory. When the digest is pinned, it decodes the records and does no
   other validation. When it is not pinned, it runs the complete validation,
   as before. A changed, added or removed file in a frozen corpus therefore
   always gets the complete validation.
3. A separate primitive always runs the complete validation, for callers that
   must check a corpus again (freezing, the pin check below).
4. One test in the `frozen` Nix suite runs the complete validation on every
   pinned corpus. It checks that each pin is the actual tree digest and that
   the fast path returns records equal to the validated records. The `frozen`
   suite runs again when a corpus or any validation module changes, so each
   pinned corpus is validated by the current validator.
5. A test that loads the v5 corpus loads it once: `conformance.progress`
   accepts already loaded records, and the progress view test uses that.
6. The historical Tcl binding scan in the complete validation skips commands
   that contain no `$`, `:` or `@` character. Such a command cannot contain a
   named parameter, so the result does not change.
7. The design documents and the open development replay task
   (`plans/20261006-development-replay-headroom.task.md`) state the new
   loading rule: the owner accepted, on 2026-10-10, that the development
   replay phase loads pinned corpora without complete validation.

8. Owner request, 2026-10-10: the pin test is its own Nix suite, `pinned`.
   Its inputs are only the pins, the pinned corpora, the SQL frontend and the
   modules that the validation imports, so it runs again only when the corpus
   or the validator changes. Nix and Python read the same pin file.

## Tests

- Pin check: complete validation of each pinned corpus passes, each pin equals
  the actual tree digest, and the fast and complete paths return equal records.
- Fast-path refusal: a copy of a pinned corpus with one changed shard byte, a
  changed extraction or ledger file, an added file or a removed file is not
  pinned, and the complete validation refuses it with its existing error.
- An unchanged copy of a pinned corpus at another path loads through the fast
  path.
- The existing tampering tests of `tests/conformance_shards_test.py`,
  `tests/conformance_evidence_test.py`, `tests/conformance_fidelity_test.py`
  and the harness suite keep passing without changes to their expectations.
- The binding-scan filter: commands with and without the three characters
  give the same `named_slots` result as the tokenizer.
- Nix invalidation tests show which file changes rerun the `pinned` suite.
- All Nix suites pass on Linux CI. The PR records the per-test and per-suite
  CI times before and after this change.

## Key points

- `conformance/corpus.py` (`load`), `conformance/corpus_shards.py` (shard
  validation), `conformance/corpus_evidence.py` and
  `conformance/corpus_acquisition.py` own the complete validation.
  `conformance/native_storage.py` (`expanded_record`) reconstructs shared
  snapshots and checks their digests and sizes.
- The fast path must give records equal to `expanded_record` output, with an
  independent mutable tree for each snapshot reference.
- The size check from the stored line is not part of this task. A stored line
  can be shorter than its canonical JSON (for example `1e5` against
  `100000.0`), so it does not give the same refusals.
- The Nix suite inputs (`build-support/tests.nix`) must contain the new
  module in each suite that imports `conformance.corpus`.
- Text follows the writing rules in `AGENTS.md`.
