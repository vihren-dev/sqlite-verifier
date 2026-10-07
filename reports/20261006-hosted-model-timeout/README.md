# Hosted model-suite deadline evidence

Created 2026-10-06. Status: awaiting the new hosted check.
Audience: reviewers and the team.

## Observed failure

The full model builder has a 420-second aggregate pytest deadline. The
600-second commands in `justfile` run host source and infrastructure checks.
The model failures are exit 124 with no model JUnit report. They reached the
last historical binding/replay tests. They are failed checks.

| Source | Executed checkout | Hosted model outcome |
| --- | --- | --- |
| [PR #43 job](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37443485808/job/112202601131) | `a1757c79` | Exit 124 in changed synthetic binding test, at 99% |
| [PR #44 job](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37443498908/job/112202644400) | `220b2dfa` | Exit 124 in changed synthetic binding test, at 99% |
| [PR #47 job](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37486282958/job/112347001173) | `fd2083af` | Fresh builder: 322 passed, 1 skipped, 300.70 seconds |
| [Main job](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37493710756/job/112372734456) | `29d2ed7a` | Exit 124 in final historical v4 replay test |

All four collected 323 cases from the same ordered 32 model test files.
PR checks execute synthetic merge commits, so their executed source identities
differ from their PR head identities. [Hosted evidence](hosted-evidence.json)
records both identities, actual derivations/runtime outputs and hashes of each
complete retained decoded job log. The compressed logs are beside that record.

PR #47 did not reuse a cached model result: its log contains the fresh builder,
collection, each accepted test and the final JUnit path. Its Lean version is
4.34.1, as in PR #43. PR #44 and main use 4.33.0. Their passing Linux peers do
not prove the timed-out macOS checks passed.

## Cause and bounded correction

The aggregate suite exceeds its 420-second budget on three hosted macOS runs.
The passing PR #47 run identifies substantial retained historical work:
v5 progress took 86.47 seconds, review-corpus replay 36.51 seconds and v4
progress 21.14 seconds. The progress test loads a frozen corpus and then calls
`progress`, which loads it again. The final binding tests also load frozen
inputs, and the final v4 test performs a fresh 100-case native sample replay.
This task retains those checks and their current subprocess limits.

[Source comparison](source-comparison.json) binds exact Git blob identities.
The progress implementation and both expensive final test files are identical
in all four executed checkouts. PR #43, #44 and #47 also have identical corpus
loader bytes. Main includes the later native-storage loader changes. The
exporter changes in PR #47 do not remove model ownership or change these tests.

The logs buffer stdout from concurrent Nix builds. Their line timestamps are
not per-case timings. They cannot isolate the cause of the speed difference
between the PR #47 pass and the other runs. Runner scheduling, concurrent
build work or native execution cost remain unmeasured possibilities. No
`boost::bad_format_string` appears in these five retained jobs; a separate
local diagnostic investigates that error.

Only `tests.model` receives a 600-second deadline. This is approximately twice
the measured 300.70-second macOS completion and adds 180 seconds beyond the
failed limit. The other six suites retain 420 seconds. The enclosing Nix
command retains its 900-second bound and CI retains its 30-minute bound.
Every file, accepted generated case, report flag and failure status remains.
This is a bounded headroom proposal, not a measured upper bound or a claim
that 600 seconds has already passed. Actual hosted completion is required.

The real Nix-rendered command check verifies complete ordered file ownership,
the two deadline policies and unchanged full-report arguments. CI routing
checks also pass. These checks build no native runtime and execute no model
case. Frozen PR #43, #44, #47 and #48 branches are unchanged.

## Temporary T03 acceptance

[PR #43 hosted Linux](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37443485808/job/112202600836)
completed the fresh full model builder: 322 passed, 1 skipped in 222.42 seconds.
The single skip is the Tcl capture case owned by the pinned upstream target.
The complete Linux job passed. Its source/runtime/log identities are retained
in the evidence record.

The [retained local Darwin receipt](https://github.com/vihren-dev/sqlite-verifier/blob/6917e3c8153af78daa6ebfc01d1f95785768e5f8/reports/20261006-lean-4341-upgrade-darwin.json)
records runtime `9f4adshxfxryj5758vmp6ayayhhf8gk2`, 323 model cases with
zero failures/errors and one Tcl skip. Its model JUnit SHA-256 is
`b91996bf3596302c72fc2b56475823ea3e5ca9dfe95814b59a35d850a654e4d7`.
Source, infrastructure and installed checks also passed in that receipt.
This temporary acceptance uses hosted Linux plus retained local Darwin.
Hosted macOS completion remains outstanding for T03, and its separate owner
review and release gates remain in force. The passing PR #47 exporter source
does not replace a complete hosted result for the frozen T03 source.
