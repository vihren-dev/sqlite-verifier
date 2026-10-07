# Requested package review changes

On 2026-10-08, added caller-module coverage for `SqliteVerifier.Candidate`,
`Belay.Sqlite.Candidate` and differently cased `belay.Sqlite.Candidate`.
The first macOS run failed for the lowercase package: Lean selected the
installed `Belay` directory and could not find the caller's sibling module.

The shared import-path helper now uses the destination filesystem's case
rules when it combines package directories. Files that collide keep the
first root's bytes. On a case-sensitive filesystem, differently cased
packages keep their separate roots. The caller test runs actual preparation,
export and kernel replay through an immutable runtime built with the fix.

The corrected macOS checks pass 18 tests: documentation links, import-path
precedence, real Lean compilation, caller proof replay, current success,
refutation and Atuin examples, exporter refusals and transitive omissions.
The initial failed log and XML are retained separately from the passing runs.
The commands have outer limits of 600 and 180 seconds, and subprocess limits
remain configured in the tests. `source.json` binds the checked helper,
test sources and actual runtime. Compressed files retain original bytes;
`sha256.json` binds each artifact.

Historical plans are exempt from current-document link checks. A regression
test confirms that a missing historical source path is allowed in plans and
still fails in maintained documentation. Restored 10 historical records from
the branch's accepted base `eb061e76`; the restoration inventory is retained.
The final integration will compare these records with the then accepted main.

These targeted results do not replace full integrated acceptance. PR #56
still waits for all four requested deliveries, both-platform checks and owner
review of the final integrated head.
