# Native runtime readiness on the executor publication

The exact reviewed integration is
`c3e8f5186e2865b5cdc0ea5af1a9d0924531752a`, with clean Claude review
`20261007T094550Z-c3e8f518` (session 58187, exit 0). Its direct parents are
reviewed T04 tip `3f68e648` and executor publication `9e91e525`.
Executor, exporter, pins, baselines and other non-T04 files retain the exact
publication bytes. Frozen corpora and workload inputs are unchanged.

The integration preserves both original review journals in their recorded
order and multiplicity. Their 110 and 161 rows merge into 207 rows; the
pending readiness review gives 208. Its undescribed working copy is not an
ancestor. The original journals, pending row and author comparisons are
retained. All 148 selected bounded integration checks passed without skips.
The model/default suite budgets remain 600/420 seconds and the replay guard
remains 120 seconds.

Both native conformance build invocations completed with exit 0:

| Platform | Handle | Exact output | Runtime files |
|---|---:|---|---:|
| Darwin arm64 | 74913 | `/nix/store/3h1ww180anyrw23dhs7bpzswhkrv2l1s-sqlite-verifier-conformance` | 17,897 |
| Linux amd64 | 34344 | `/nix/store/ixl6nwa1nk8ah8138axkqkgian4a27bc-sqlite-verifier-conformance` | 17,936 |

These fresh pinned build invocations used already existing exact Nix outputs.
The receipts state this explicitly and compare every runtime file before
and after. They do not claim compilation from scratch. Each build used the
existing resource guard and a 900-second process-group bound. The capture
helper's separate 1200-second outer bound includes identity capture.
T15 released Darwin before its build. Both build leases were released after
the actual terminal outcomes, before other coordinated native work.

The source-only archive has SHA-256
`ee3aac147f2390dd28e47f31de7bff56451c08122a7634ecc75102ff994db292`,
72,294,400 bytes and 1,113 source entries. Its public revision, original
archive command, complete file hashes and link are retained. The source
archive is identified rather than duplicated in this report. Linux's
pinned-Python preflight checked every transferred source and helper byte.
All 16 retrieved Linux originals match their remote hashes and lengths.

Complete source, runtime, helper, archive, Python and declared SQLite engine
identities are retained. Each platform uses Lean 4.34.1 and Python 3.14.7.
Source inputs and full runtime identities match before and after. Actual
UTC/monotonic boundaries, machine/filesystem observations, resource-guard
results, Nix evaluation/build commands and original streams remain intact.
No native or model replay, profile or performance phase ran. These receipts
establish runtime readiness; T04 remains **IN PROGRESS**, and its prior
valid Linux target miss remains unchanged.

`raw-sha256.json` binds all 47 gzip artifacts to their exact original bytes.
Original build-command files use archival `commands/` directories so the
repository's generated `build/` ignore rule cannot exclude them. Linux's
original manifest keeps the remote directory names; validation maps only
that command's archival path and retains its exact original bytes.
`public-archive-validation.json` records the separate clean public-archive
check of revision `77883deb`: both scripts passed with 47 tracked gzip
artifacts. This derived result is outside the raw build-artifact manifest;
`validate.py` does not check it.
Run the bounded read-only checks from the repository:

```sh
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-executor-runtime/validate.py
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-executor-runtime/check_mutations.py
```

The second check refuses false runtime/acceptance claims and changes to the
build bound or journal order even when the changed artifact hashes agree.
