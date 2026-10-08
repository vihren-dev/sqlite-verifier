# Replay acceptance after approved deliveries

Integrated accepted main `c1dea71b`, including delivered PRs #57, #53 and
#50, into approved PR #59. The reviewed feature commits remain unchanged.
The corpus-shard conflict retains both bounded snapshot reconstruction and
T17's recording validation. The expander enforces the complete logical byte
limit before recording validation; redundant expanded serialization is removed.
All original parent journals remain ordered subsequences, including repeats.

The complete macOS command exits zero:

```sh
nix develop path:./nix --command timeout 2400 just test-full test-nix
```

All nine Nix suites pass 577 tests without failures, errors or skips.
Source checks pass 461 tests and 35 subtests. Infrastructure checks pass
102 tests. Original JUnit timestamps and output paths distinguish reused
outputs from new builders. `receipts.json` records every suite. Compressed
files retain original logs, JUnit and parent journals. `current-source.json`
binds the integrated acquisition, loading, replay and build inputs.
`sha256.json` binds the retained artifacts.

These checks do not establish the fresh performance target. Integrated
loading and native helpers changed, so standalone timing on both native
platforms remains required. The outer guard stays 120 seconds and the target
stays strictly under 30 seconds. Earlier timing records remain bound to
their original sources. Independent review, fresh hosted checks and normal
merge remain pending. The owner approves PR #59 when it is ready.
