# Optional upstream catalog tests status

Status: DONE. Created and completed 2026-10-06.

Task: [optional upstream catalog tests](20261006-optional-upstream-catalog.task.md).
Source: [issue #38](https://github.com/vihren-dev/sqlite-verifier/issues/38).

Relevant files: `tests/conformance_catalog_test.py`,
`conformance/upstream_catalog.py`, `build-support/tests.nix`,
`tests/nix_suites.json`, `tests/runtime_support.py`.

## Progress

- 2026-10-06: Confirmed the shared fixture indexes the environment variable
  directly. All three archive-dependent cases use it. The Nix upstream suite
  supplies the pinned archive and selects the module. Created the task record
  before code changes in an isolated workspace based on `4a425828`.
- 2026-10-06: The fixture now skips only an unset variable and fails a configured
  path without a `test` directory. Six bounded subprocess cases exercise the
  actual catalog module with absent, empty, invalid, missing-member,
  extra-member and valid inputs. Catalog definitions and Nix ownership remain
  unchanged.
- 2026-10-06: Fixed review finding `20261006T084650Z-f1617c4a#1`. An empty
  configured value now fails before path conversion. The regression runs that
  case from a directory with a valid catalog, so it cannot accept `.` as the
  archive by accident.
- 2026-10-06: Completed all acceptance checks and independent review. Task and
  status records are DONE. The final append-only review entry is pending for
  the next integration commit, as required by the review workflow.

## Validation and review

- Used `nix develop path:/Users/tzankomatev/work/sqlite-verifier/nix --command`
  for all checks. The host Python has no pytest; the supported pinned shell
  supplies it.
- `timeout 30 python3 -m pytest -q tests/test_conformance_catalog_environment.py`:
  6 passed in 2.39 seconds. Each child pytest run has a 10-second timeout.
- `timeout 20 env CONFORMANCE_UPSTREAM=/nix/store/lhpfjyh7vn7n5m196n4pqr1narbcnawc-sqlite-conformance-upstream-3.51.0 python3 -m pytest -q tests/conformance_catalog_test.py tests/conformance_sampling_test.py::test_fixed_catalog_and_explicit_file_exclusions`:
  4 passed in 0.84 seconds.
- `timeout 15 env -u CONFORMANCE_UPSTREAM python3 -m pytest -q tests/conformance_sampling_test.py::test_fixed_catalog_and_explicit_file_exclusions`:
  1 passed; the pure check runs without the archive.
- `timeout 900 nix-build build-support/default.nix -A tests.upstream --out-link build/nix-upstream --option sandbox true --option sandbox-fallback false --extra-experimental-features 'nix-command flakes'`:
  58 passed in 2.63 seconds, with no skips. All three original catalog cases
  passed. Immutable JUnit evidence:
  `/nix/store/q61g66skga5wr74vk5zpjyc4s3dg6x32-sqlite-verifier-test-upstream-1/junit.xml`.
- The sandboxed Claude review of `f1617c4a` failed with API DNS error
  `ENOTFOUND` (exit 3), recorded as `20261006T083643Z-f1617c4a`. Automatic
  approval rejected the first network escalation before execution. After the
  user authorized Claude API reviews, the required retry completed with no
  must findings and one should finding, recorded as
  `20261006T084650Z-f1617c4a`. The finding is fixed and its resolution is logged.
- After the review fix, the six subprocess cases passed in 2.36 seconds.
  The sandboxed Nix upstream suite rebuilt: 58 passed in 5.62 seconds, with no
  skips. Latest immutable JUnit evidence:
  `/nix/store/n53v5snbfma8j650l779gfp38aylg4f7-sqlite-verifier-test-upstream-1/junit.xml`.
- Claude reviewed refactor commit `0f2c00a8` with no findings (exit 0), recorded
  as `20261006T084824Z-0f2c00a8`. All review findings are resolved. The final
  review entry remains pending in `reviews/log.jsonl`; earlier outcomes and
  the finding resolution are committed in the refactor.
- 2026-10-06: Integrated with maintenance and documentation rules.
  Combined source validation passes all 125 cases in 7.89 seconds with
  a 60-second command limit, including the six catalog subprocess cases.
  The integration retains every record from both review histories,
  including the final catalog correction review.
