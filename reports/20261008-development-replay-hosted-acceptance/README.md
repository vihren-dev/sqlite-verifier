# Hosted development replay acceptance

Created 2026-10-08. Audience: team and reviewers.
Task: [T04c](../../plans/20261006-development-replay-headroom.task.md).

CI `37743066830` succeeds for reviewed head `d264bba3`. The actual CI
merge source is `4d492b4b`; GitHub comparison reports zero changed files
against the reviewed head. The comparison response is retained. Hosted Linux runs
all nine Nix suites and passes 532 tests without failures, errors or skips.
Actual infrastructure checks pass 99 tests. Source checks pass 417 tests and
35 subtests, with two explicit optional reviewer-tool skips and 99 deselections.
This infrastructure scope does not run fresh installed-package acceptance.
The macOS PR job skips execution; its successful job status is not native
acceptance. Retained fresh local macOS records supply that evidence.

The exact GitHub artifact ZIP has SHA-256
`91e3b3135a3ae5557172640521d8627ce0c0d7fa2a8b4cdabf343338efd662ee`,
which matches the workflow metadata. All 17 members are retained individually.
The job log is the connector's decoded UTF-8 response, retained with its hash.
Suite assignment is checked against the actual owned test modules; all nine
suites are represented. Original phase records preserve commands, exits and
actual runtime identities. `manifest.json` binds every retained artifact.

The first download client, ambient Python urllib, refused the issuer chain.
The existing system curl client downloaded the bytes with unchanged default
TLS verification. No TLS check was disabled, and the original GitHub digest
matches. `retrieval.json` records the client distinction.

These correctness results do not replace the standalone timing measurements
on reviewed source `2006755a`. Their original macOS 10.65-second and Linux
24.78-second receipts remain separate. No timing rerun is claimed.
Independent hosted-evidence review and normal delivery remain required.
T04c is IN PROGRESS.
