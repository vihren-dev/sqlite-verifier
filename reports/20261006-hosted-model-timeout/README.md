# Hosted model-suite deadline evidence

Created 2026-10-06. Status: DONE; both required hosted checks passed.
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
failed limit. The later, separate local PR #48 observation takes 484.735
seconds under only the reviewed 600-second model invocation. That leaves
115.265 seconds within the proposed limit and shows actual work above 420
seconds. Its distinct source and unchanged branch limit are recorded below.
The other six suites retain 420 seconds. The enclosing Nix
command retains its 900-second bound and CI retains its 30-minute bound.
Every file, accepted generated case, report flag and failure status remains.
The limit is not a measured upper bound. Both required hosted whole jobs now
pass for the reviewed published source, as recorded below.

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

## Current timeout-task acceptance

[PR #49](https://github.com/vihren-dev/sqlite-verifier/pull/49) publishes reviewed
tip `b7883400`. [Linux job](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37512848112/job/112438177974)
completed successfully. It executed merge `4056410c` with the reviewed
600-second policy. Its fresh model builder completed 322 passed and one Tcl
skip in 177.33 seconds. The retained original XML contains 323 unique cases
from all 32 owned model files. [The Linux receipt](acceptance/linux/receipt.json)
binds the executed source, recipe blob, runtime, exact case identity digest,
original ten-report ZIP and decoded log. The ZIP matches GitHub's digest.
Other Nix suites can reuse their source-bound successful outputs.

The [qualified local PR #48 evidence](acceptance/pr48-darwin-qualified.json)
records a separate mutation-corrected source, `9e3b4419`, with 322 passes and
one Tcl skip of 323 model cases under only the reviewed 600-second invocation
override in 484.735 JUnit
seconds. Its earlier configured-420 checkpoint `83edc417` failed without JUnit
after a 422.825-second file-write interval and a Nix formatting error. These
are different source checkpoints; the record retains that distinction and
the original receipt hashes. It does not turn PR #48's configured 420-second
check into a pass. It provides additional observed work above 420 seconds.

[PR #49 macOS](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37512848112/job/112438177629)
also completed successfully. Its fresh model builder has 322 passes and the
same Tcl skip of 323 cases in 411.41 seconds (original JUnit: 411.368). The
ordered case identity digest exactly matches Linux and represents all 32
owned files. Its 124.65-second v5 progress and 51.66-second review-corpus calls
show the same substantial historical work as the earlier jobs. The passing
suite has only 8.59 seconds within the former 420-second limit and 188.59
seconds within 600 seconds; the separate local PR #48 observation remains
the longer measured suite at 484.735 seconds.

[The Darwin receipt](acceptance/darwin/receipt.json) binds the original ten-report
ZIP, its GitHub digest, decoded log, actual runtime, executed merge and recipe.
Both downloaded archives match GitHub digests, and all 20 original XML reports
have zero failures/errors. The entire [CI run](acceptance/completion.json) is
successful, including infrastructure and installed acceptance on both hosts.
Both use Lean 4.33.0 from the main-based published source; this receipt does
not replace the separate frozen T03 source's platform or owner gates.

The timeout task is DONE. PR #49 is merged at main `d8faab74`. The adopted
recipe has the exact tested Git blob, as recorded in the completion receipt.
This receipt update does not merge, repush or change any frozen PR branch.
Release was skipped, and the earlier configured-budget failures remain retained.
