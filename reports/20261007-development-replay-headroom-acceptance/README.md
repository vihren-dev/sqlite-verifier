# Fresh development replay on the publication base

The task remains **IN PROGRESS**. The one fresh phase on macOS meets the
less-than-30-second target. Linux misses it. Both receipts pass the evidence
checks, and the unchanged phase guard is 120 seconds.

| Platform | Fresh report phase | Outer report call | Target | Result |
|---|---:|---:|---:|---|
| macOS arm64 | 21.434975332995236 s | 22.19781625 s | <30 s | Meets target |
| Linux amd64 | 39.57022682100069 s | 40.432509126 s | <30 s | Misses target |

These are separate observations on coordinated hosts. They are not paired
speedup measurements against the prior runtime. Both reports loaded and
checked all frozen bindings before selection. They replayed the same 184
selected identities from the full denominator of 4378, with the same exact
profiles, SQL and ordinary file storage. All 184 native comparisons passed.
The current model classified all 184 cases as `MODEL_UNSUPPORTED`; this does
not establish agreement within supported model semantics.

## Source and runtime identity

Both phases used reviewed source
`5d15607fdf78d0a209b539ca158939739b54d377`. It merges reviewed main
`bc9e2dce58f755b608cf00e545162257b81ab51a` with the reviewed snapshot and worker
units. Merge review `20261007T074749Z-5d15607f` is clean.
The source-only archive has SHA-256
`86b96911dae99a77ef8158c8ac53c548b69896744de904365545ded78bc4f422`
and 59,648,000 bytes. Each host checked all 933 regular archive files and the
`CLAUDE.md -> AGENTS.md` link. The complete source manifest is retained.

Each host built its own pinned conformance runtime from that exported source:

- Darwin: `/nix/store/2w1dv3hhnrcjrcm7qp43jpdbxsgvr6wl-sqlite-verifier-conformance`.
- Linux: `/nix/store/rhinzr7jq41azsh6s8i8dmndi7idnv3k-sqlite-verifier-conformance`.

Both use Lean 4.34.1 and Python 3.14.7. The receipts retain actual resolved
Python paths and hashes, all 17,886 Darwin and 17,925 Linux runtime file hashes,
and every native engine used. These selected profiles use SQLite 3.51.0.
Full source, runtime, helper, archive, Python and native-library identities are
equal before and after each phase. The report's parser and compiled-model
hashes match the installed runtime file hashes. The build logs are retained.

The same two public capture helpers ran on both hosts. Their exact bytes and
before/after hashes are retained separately from the source archive. The
capture helper has a main guard for spawned workers. It calls
`report(..., temporary_root=..., fixture_paths=...)` directly once, through the
existing `run_command` process-group harness at the unchanged 120-second
bound. Its exit code tests receipt validity. The separate `underTarget` field
tests the 30-second acceptance target.

## Actual timing and storage observations

Darwin ran from `2026-10-07T08:02:24.849652+00:00` to
`2026-10-07T08:02:47.048556+00:00`; monotonic nanoseconds were
`34332743435458` and `34354941251708`. Its storage root is
`/Users/tzankomatev/work/sqlite-verifier-headroom/build/20261007-t04c-acceptance/darwin/native-storage`.
Linux ran from `2026-10-07T08:12:51.299500+00:00` to
`2026-10-07T08:13:31.731999+00:00`; monotonic nanoseconds were
`420416899786793` and `420457332295919`. Its storage root is
`/var/tmp/sqlite-verifier-t04c-20261007.4yNihbCP/linux/native-storage`.
Each receipt includes all 184 unique actual `case.db` paths in input order,
their common private root and observed cleanup. Source code checked the files
while they existed. A separate Linux transfer check also found the selected
storage empty after the run.

Linux observed ext4 on `/dev/md127`, mounted `rw,noatime` at `/` before and
after. Its load averages changed from `[0.39990234375, 0.2021484375,
0.19873046875]` to `[1.220703125, 0.45263671875, 0.28466796875]`.
Darwin load averages changed from `[6.08349609375, 5.521484375, 4.921875]` to
`[5.2236328125, 5.34716796875, 4.87744140625]`. Host leases excluded other
coordinated heavy work. The records include full machine, CPU, memory, disk
capacity and filesystem observations. They do not claim zero host load.

Darwin's original GNU `df` described the sealed system snapshot through the
macOS firmlink. That raw observation remains unchanged. The explicitly
**after-only** native reconciliation identifies writable APFS Data on
`/dev/disk4s5`, mounted at `/System/Volumes/Data`. The actual directory device
number, `16777242`, was retained before and after the phase and matches that
mount in the later observation. No earlier volume text was reconstructed.

The helpers read full identity bytes before and after, outside the report
phase. OS file caches were not flushed, and residency was not observed. The
reports were computed freshly once. Neither fresh phase has stage, CPU or
wait instrumentation. The new evidence cannot attribute Linux's remaining
time to loading or native wait. The separately retained prior instrumented
diagnostic supplies hypotheses for a later authorized unit.

## Retained failures and validation

Three preflight failures preceded measurement: archive lookup in the Jujutsu
workspace produced an empty tar; the first Darwin metadata helper passed a
directory to `diskutil`; the initial Linux shell had no ambient `python3`.
Their retained summaries and the empty archive identify the failures and
confirm that no phase ran. Original UTC and monotonic timestamps were not
serialized for these failed setup commands. The metadata failure retains its
recorded message, not an original complete traceback. Successful setup used
the shared Git object store for the public archive, resolved filesystem
devices, and the existing pinned Linux Python. No measured phase was rerun.

`raw-sha256.json` binds all 37 gzip artifacts and their exact original bytes.
The archive is identified by its public commit, byte count and hash; it is not
duplicated in this evidence directory. `receipt.json` summarizes results,
terminal handles and qualifications. Full reports, original phase command
streams, capture logs, helpers, before/after manifests, conditions, source and
transfer checks, build logs and failures are retained.

Run the bounded read-only validator from the repository:

```sh
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-headroom-acceptance/validate.py
nix develop path:./nix --command timeout 15 python3 -B \
  reports/20261007-development-replay-headroom-acceptance/check_mutations.py
```

It checks retained bytes, public source and helper bindings, runtime identity,
all historical selected identities/profiles/verdicts, timestamps, actual paths,
cleanup and the separate target fields. A valid Linux miss remains a miss.
The mutation check refuses four independent corrupt identity, native-library,
fixture-path and target observations. Both bounded checks pass.
The prior receipts and all frozen corpus bytes remain unchanged.
