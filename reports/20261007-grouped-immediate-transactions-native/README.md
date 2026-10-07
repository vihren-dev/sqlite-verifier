# Complete native transaction acceptance on macOS

Audience: task reviewers.

Reviewed source `2c9d7322` runs the complete refreshed `model`, `frozen` and
`harness` Nix targets in the hardened macOS sandbox. All 329 checks pass with
no failures, errors or skips. The [receipt](receipt.json) binds the exact
source inputs, outputs, original JUnit files and compressed build log.

| Suite | Passing checks | New transaction checks | JUnit duration |
| --- | ---: | ---: | ---: |
| model | 51 | 0 | 63.900 seconds |
| frozen | 152 | 7 | 272.087 seconds |
| harness | 126 | 6 | 2.385 seconds |

The suite hang guard is 1,200 seconds and each test has a 300-second limit.
The complete local command has a 1,800-second process guard. JUnit durations
describe each suite; they are not an outer command duration.

All 13 new transaction checks execute in their assigned targets. Existing
model, frozen evidence and harness behavior remain selected. No formatting
failure occurs in this run. The cause of the old unfinished run remains
unexplained; its original logs and limited diagnostic failures are unchanged.

This record proves local macOS acceptance. Linux, hosted acceptance and
normal PR delivery remain required. The frontend closure and actual Nix
ownership checks are recorded in the task's
[status](../../plans/20261006-grouped-immediate-transactions.status.md).
