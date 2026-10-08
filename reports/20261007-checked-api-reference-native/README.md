# Clean native API reference acceptance

Both native builds pass for exact reviewed source
`2df58fd1ca2cdfc01a822e5b36602f43140f0809`, tree
`374f1bb50c19b81c91f859bda5205a890f30d32d`. This source contains T18b over
reviewed executor `9e91e525`. It excludes T15 and T07. The earlier mixed-source
[receipt](../20261006-checked-api-reference/native-acceptance.json) is unchanged.

Both references contain 21 public modules, 323 rendered declarations, 1,167
HTML pages and 829,618 valid local links. They correct the same 178 upstream
links. The Lean 4.34.1 inventory checks all 259 authored declarations, with
zero missing, ordinary or unclassified entries and 942 explicit exclusions.
Every inventory source digest and both output pin files match the reviewed
source. Rendered declarations include generated declarations and are a
different count from authored coverage.

| Platform | Actual terminal exit | Recorded reference build phase | Output |
| --- | --- | --- | --- |
| Darwin | 0 | 5 minutes 5 seconds | `/nix/store/bmmr98hxwh7yx102m8925ii8wai0a7l5-sqlite-verifier-api-reference-2df58fd1ca2c` |
| Linux | 0 | 6 minutes 56 seconds | `/nix/store/gcvsljvadiy8in9xpbwafs6kayyfk9qk-sqlite-verifier-api-reference-2df58fd1ca2c` |

[Native acceptance](native-acceptance.json) states the exact scope and
qualifications. [Raw hashes](raw-sha256.json) identify every retained payload.
[Darwin originals](darwin.tar.gz) contain its logs and metadata.
[Linux originals](linux.tar.gz) are the exact retrieved receipt archive,
including the capture helper, commands, exit statuses, timestamps and source
manifest. Archive headers only package the files; each original file's bytes
are identified by its raw hash.

Darwin's original attempt ended with exit 137 after the owner authorized
SIGKILL of the verified process group. The cancellation record and complete
console log remain in the Darwin archive. An ambient retry exited 127 because
`timeout` was unavailable, before Nix started. The successful authorized retry
used the pinned Nix shell, unchanged pins and 1,800-second deadline, with a
10-second forced cleanup guard. Session 49492 returned actual exit zero.
`retry-invocation.json` records that parent-agent observation and exact argv.
No retry UTC or monotonic boundaries were captured. The source snapshots span
all attempts and do not measure retry duration. They check 968 tracked entries
(967 regular files and the documentation symlink); they explicitly exclude
the pending review journal. No proxy or credential configuration changed.

Linux's output was invalid before its single build. The exact recipe ran from
11:07:30.444798 to 11:14:28.795936 UTC on 2026-10-07: 418.351160823 seconds
by its monotonic clock. Its 1,800-second bound, resource guard and hardened
sandbox passed. All 969 tracked entries, executable bits and symlink target
match before and after. The source archive and capture helper are unchanged.
The remote task directory remains `/var/tmp/sqlite-verifier-t18b-reference.stMbNq`.
The first local audit expected an older Nix derivation JSON layout. The
corrected audit checked the actual version-4 layout; no build was repeated.

Each generator emitted four known upstream Std.Time equational-lemma heartbeat
warnings. Generation and complete link validation passed on both platforms.
These are native reference results. Ordinary integrated checks, both hosted
artifact builds and normal PR delivery remain required. T18b is IN PROGRESS.
