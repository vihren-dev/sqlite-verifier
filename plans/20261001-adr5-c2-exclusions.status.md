# ADR 0005 C2 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [exclusion narrowing](20261001-adr5-c2-exclusions.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

Runtime extraction retains unsupported contexts and tracks auxiliary lifetimes. Ordinary eval and
read-only onecolumn/exists calls are supported, including mixed helper sequences.
Verified pure row scripts are supported; other bodies remain excluded. Selection
preserves preceding reasons.
Detached in-memory prefixes recover after faithful native replay. File attachment
prefixes remain excluded. Yield improvement has not yet been measured.

## Progress

- 2026-10-01: Read the Tcl proxy, assertion event consumer and pilot selection
  while C1's full regression ran. Recorded required observable outcomes and
  rejecting tests before implementation; frozen evidence remains unchanged.

- 2026-10-01: Replaced overwriting selection branches with a pure accumulated
  reason policy. Context, failed Tcl expectations, missing SQL observations,
  continuation after an SQL error and the selection cap all survive together.
  Per-instance reports expose the full exclusions array and retain the existing
  result string for consumers. Acquisition failures also enter that array;
  extractor source identity includes the policy module. Upstream/frozen replay
  and document checks: 7 passed in 4.65 seconds. Helper semantics, context
  lifetime narrowing and measured yields remain open.

- 2026-10-01: Runtime candidates retain helper kinds in prefixes and assertions.
  Native acquisition uses the SELECT-only preparation guard and native readonly
  flags for row helpers; writes and setting PRAGMAs are refused. Tcl fidelity
  applies exists/onecolumn semantics to ordinary native rows without changing
  evidence. Tests cover first-column, existence, NULL and empty results, prefix
  helper reads, wrong expectations and writing helpers. Mixed helper sequences
  and row scripts remain named exclusions pending their own faithful checks.
  Split the assertion event consumer out of the 196-line pilot module to keep
  files below 200 lines, preserving its public import. Upstream/record/profile/
  document checks: 26 passed in 5.03 seconds. Built the pinned Tcl testfixture and
  verified actual helper behavior against src/tclsqlite.c and the standalone
  tests/upstream_helpers.tcl check (HELPER_SEMANTICS_OK). C2 remains open.

- 2026-10-01: Mixed eval/onecolumn/exists calls now compare per original Tcl
  call, using UTF-8 source spans and native statement boundaries. Helper spans
  enforce SELECT-only preparation even beside ordinary writes; statements that
  cross calls are refused. Tests cover multi-statement eval, Unicode/trailing
  comments, semicolon-free calls, wrong results and a writing helper. Real pinned
  Tcl extraction exposed newline-only joining as a mechanical fidelity failure:
  separate calls without semicolons merged into invalid SQL. Joining with a
  newline-delimited semicolon fixes it without changing original call SQL.
  tests/upstream_helper_calls.test now yields one recorded case through the real
  proxy/harness, and its fresh native replay passes. Upstream/record/profile/docs:
  27 passed in 5.06 seconds. Row scripts, context recovery and yields remain open.

- 2026-10-01: The real Tcl proxy recognizes empty/basic braced expr row bodies,
  rejecting command substitution, function calls, namespace references and
  variable traces. Side-effecting/unrecognized bodies keep their exclusion.
  Pure scripts use Tcl's empty-result semantics while ordinary native rows and
  RETURNING evidence remain unchanged. The pinned harness now has five checks:
  mixed helpers and pure SELECT/RETURNING scripts record three cases; explicit
  mutation and a variable-read trace remain excluded. All recorded cases pass
  fresh native replay. Upstream/record/profile/docs: 28 passed in 5.09 seconds.
  Context lifetime recovery, profile-aware extraction and yields remain open.

- 2026-10-01: Auxiliary connection lifetimes now end on actual Tcl command
  deletion (close can delete the command before its execution-leave trace).
  After closure, recovery requires read-only SQL on the same main database
  generation, unchanged settings, no auxiliary read inside a primary transaction
  and exact fresh-prefix Tcl outcomes/results. These conditions prevent untyped
  Tcl values from hiding storage-class differences under another snapshot.
  Auxiliary writes/different files stay excluded; reset does not close live
  auxiliary handles. Renamed commands retain an unsupported context across
  resets. The pinned Tcl context test records one valid recovery and refuses
  live/reset-live handles, uncommitted reads and auxiliary writes; fresh native
  replay passes. Context/upstream/record/profile/docs: 32 passed in 5.54 seconds.
  Attached-database recovery, profile-aware extraction and yields remain open.

- 2026-10-01: Attachment lifetimes now use the native database inventory after
  each Tcl call. Successful DETACH can promote the complete preceding SQL into
  setup; fresh native replay checks its results before recording a candidate.
  Only literal in-memory attachments are allowed during setup. Live attachments,
  failed DETACH and external files remain refused. The real pinned Tcl harness
  records two recovery cases, and both pass fresh native replay. Full hermetic
  model suite: 84 passed in 142.48 seconds. Final context/document checks:
  7 passed in 0.58 seconds. Profile-aware extraction and measured yields remain open.

- 2026-10-01: Fixed a prerequisite for profile-aware extraction: prefix
  minimization now preserves the native output version, typed parameter bindings,
  requirements and profile/clock inputs when it re-records a trial. Previously it
  used legacy acquisition, so output cases could not lose redundant setup and
  profile evidence could not survive minimization. Tests verify both output-only
  and controlled-clock records retain exact initial state and trace while setup
  shrinks. Upstream/frozen replay/document checks: 17 passed in 5.80 seconds.
  Tcl profile integration and measured yields remain open.
