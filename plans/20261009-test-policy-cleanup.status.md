# Status: remove tests of dependency behavior

Created 2026-10-09. Status: DONE.
Task: [task](20261009-test-policy-cleanup.task.md).

Relevant files: the eight test files named in the task,
`tests/nix_suites.json`, `tests/conformance_frontend.json`.

## Progress

- 2026-10-09: review of all 498 test functions on main `2954eb7` against the
  testing rules. Task and status files created.
- 2026-10-09: removed and reduced the tests. The 28 tests in the changed
  files pass. The source suite has 457 passes; its 9 failures and errors come
  from the local runtime root (an older Nix store build without `examples/`)
  and are in files that this change does not touch. CI runs them on a fresh
  build.
- 2026-10-09: review of `e817a350` by Codex: no findings. Task DONE.

## Removed and reduced tests

The authored corpus cases stay. For each case, `native_replay` replays the
frozen record against SQLite and fails on any changed output, and the model
comparison classifies it. So SQLite stays the oracle for every removed
assertion. The removed tests restated SQLite's results by hand.

| Test | Reason | Our code that stays covered, and by what |
|---|---|---|
| `conformance_authored_queries_test::test_aggregates_empty_single_and_null_groups` | SQLite aggregate semantics | Record transport: `test_catalog_keeps_legacy_sql_and_complete_outputs` |
| `conformance_authored_queries_test::test_join_coalesce_cast_and_real_arithmetic` | SQLite join, COALESCE and CAST semantics | REAL bits: `test_bound_storage_classes_and_integer_edges` |
| `conformance_authored_queries_test::test_json_types_missing_paths_and_empty_shape` | SQLite JSON functions | Empty output shape: `test_catalog_keeps_legacy_sql_and_complete_outputs` (`columnCount`) |
| `conformance_authored_boundaries_test::test_added_default_values_and_affinity` | SQLite default affinity | `test_explicit_catalog_native_replay_and_classification` |
| `conformance_authored_boundaries_test::test_not_null_add_depends_on_existing_rows` | SQLite `ADD ... NOT NULL` rules | Same |
| `conformance_authored_boundaries_test::test_rejected_add_forms_leave_schema_and_rows_unchanged` | SQLite rejected `ADD` forms | Same |
| `conformance_authored_boundaries_test::test_native_valid_definitions_have_concrete_rows` | Definitions that SQLite accepts | Model refusal: `test_validity_boundaries_are_unsupported_without_profile_gate` |
| `conformance_authored_boundaries_test::test_native_invalid_definitions_are_real_errors` | Definitions that SQLite rejects | Same |
| `conformance_authored_test::test_defaults_and_added_column` | SQLite defaults | `test_catalog_keeps_legacy_sql_and_complete_outputs` |
| `conformance_authored_test::test_transaction_trigger_cascade_and_direct_counts` | SQLite trigger and cascade counts; duplicate | `conformance_record_test::test_record_outputs_and_direct_changes` |
| `conformance_authored_test::test_upsert_all_returning_branches` | SQLite UPSERT and RETURNING | `test_catalog_keeps_legacy_sql_and_complete_outputs` |
| `conformance_authored_test::test_constraint_failures_and_statement_rollback` | SQLite constraint and ABORT semantics | Same |
| `conformance_authored_review_test::test_cast_outputs_preserve_exact_real_bits` | SQLite CAST semantics | REAL bits: `test_bound_storage_classes_and_integer_edges`; replay detects a changed bit: `test_review_shard_load_and_fresh_replay` |
| `conformance_authored_review_test::test_deferred_foreign_key_commit_boundaries` (reduced) | Removed: SQLite error codes and row values | Kept: open transaction, separate visible and persisted snapshots |
| `conformance_authored_transactions_test::test_commit_publishes_schema_defaults_indexes_and_writes` (reduced) | Removed: SQLite change counts and row values | Kept: open transaction, persisted state until COMMIT, published state after COMMIT |
| `conformance_authored_transactions_test::test_explicit_rollback_removes_schema_and_write_group` | SQLite ROLLBACK | Observer: the reduced commit test |
| `conformance_authored_transactions_test::test_savepoint_rollback_preserves_outer_prefix` | SQLite SAVEPOINT | Same |
| `conformance_authored_transactions_test::test_first_failure_retains_uncommitted_prefix` (2 cases) | SQLite first-failure state | Same |
| `test_checked_public_docs::test_documentation_checks_terms_and_reports_the_source_location` (4 cases) | Lean's Verso checks, with a probe that sets the option itself | The Lean build of our modules with `doc.verso` |
| `conformance_dqs_test::test_library_default_and_frontend` (reduced) | Removed: SQLite's double-quoted string fallback | Kept: default DQS configuration, now with the compile-option check; frontend refusals |
| `conformance_pipeline_test::test_connection_dqs_profile` | Repeated the DQS configuration check and the SQLite quirk | `conformance_dqs_test::test_library_default_and_frontend` |

`test_toolchain_smoke.py`: the module docstring now names only the pinned tool
identities.
