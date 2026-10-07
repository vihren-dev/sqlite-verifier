# Executor acceptance after the main refresh

Audience: task reviewers.

The retained job responses distinguish execution from a skipped platform.
At `46bd04b5`, [run 37615200892](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37615200892)
completed the full pinned checks and artifact retention on both native hosts.
The [job response](complete-native-46bd04b5.json) records those actual steps.

The owner refreshed this branch with accepted main and the split suites at
`935e42db`. [Run 37628447150](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37628447150)
passes Linux execution. Its macOS PR job executes only the skip step; it is
not a macOS acceptance pass. The [response](refreshed-head-935e42db.json)
retains that distinction. The previous complete native run is unchanged.

All 74 owner-approved source, pin and baseline files match their original
[hashes](approved-source.json). The deliberate baseline drift remains the
approved owner exception; its failed check is not relabeled.

The refreshed merge omitted 15 rows from the previous committed review journal
and changed its order. The repair preserves the entire refreshed journal and
the original history as ordered subsequences, including repeated rows. It also
restores the original pending `0855f956` review from the retained working-copy
revision. [The preservation record](journal-preservation.json) binds the
211-row result before the new review is appended. No existing row is edited
or deleted. This repair changes no production or test input.

Main later advances through accepted PR #54 to `98b90975`. The integration
retains that CI follow-up and resolves only the journal conflict. Its
[preservation record](main54-journal-preservation.json) verifies both complete
histories and all 74 approved source files. The original job responses above
remain evidence for their exact source revisions.
