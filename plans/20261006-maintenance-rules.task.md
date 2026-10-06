# Maintenance rules and the default execution profile

Created 2026-10-06. Status: IN PROGRESS.
Status file: [status](20261006-maintenance-rules.status.md).
Sources: [issue #22](https://github.com/vihren-dev/sqlite-verifier/issues/22)
and the policy portion of [issue #25](https://github.com/vihren-dev/sqlite-verifier/issues/25).

## Observable behavior when done

- `AGENTS.md` requires replacement code and all its callers to change together.
  Old implementation paths, compatibility aliases and new legacy markers are
  prohibited. The rule is reviewed before the first public release.
- `DEFAULT_PROFILE` names the existing default SQLite execution profile.
  Selection and generated Lean inputs keep their current meaning. All callers
  use the new name; no alias for the old name remains.
- `AGENTS.md` requires each stable Lean release to be adopted within two weeks,
  in a separate change, until the project has users. Release candidates are
  excluded. If a dependency has no matching tag, its latest tag is tested with
  the new toolchain. A failed build is recorded in the upgrade issue, and the
  upgrade waits for the dependency. SQLite execution profiles are excluded.
- The remaining executor and schema lookup cleanup is tracked by public issues
  #21 and #15. This task does not change their semantics. Issue #25 still needs
  the toolchain upgrade in #24.

## Acceptance checks

The existing profile, CLI input and SQL translation tests run with bounded
timeouts. They verify exact version selection, refusal of unknown profiles,
the generated engine identity and the existing default behavior. A source
search finds no obsolete constant or compatibility alias. Review checks the
policy wording against the two public issues.

## Relevant code and constraints

`migration_check/profiles.py` owns the default constant and version selection.
`migration_check/sql_model.py` uses that constant as its default parameter;
`tests/test_profiles.py` checks version selection. The historical conformance
corpora and their replay readers are evidence, not replaced implementation
paths. They remain valid under the no-compatibility rule. The actual Lean
upgrade is a separate task.
