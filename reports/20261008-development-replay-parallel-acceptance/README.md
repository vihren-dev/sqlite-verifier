# Fresh development replay acceptance

Created 2026-10-08. Audience: team and reviewers.
Task: [T04c](../../plans/20261006-development-replay-headroom.task.md).

Both fresh standalone phases pass the strict target on reviewed source
`2006755a`: 10.649971125 seconds on macOS arm64 and 24.784056110 seconds
on Linux amd64. Their outer report calls take 11.488487166 and
25.615881044 seconds. The process-group guard remains 120 seconds.
One phase ran on each host. No timing rerun followed either result.

Each report fully loads and binds the 4,378-case denominator, compares
all 184 selected native cases, and classifies the current model. The exact
selected identities, profiles, policy, case results and verdicts match
historical v5. All native comparisons pass. Every model classification is
`MODEL_UNSUPPORTED`; this establishes no supported-model agreement.
Actual paths identify 184 distinct ordinary-file fixtures per platform,
and every private fixture is cleaned. Complete source, runtime, Python,
helpers, archive and native-library identities match before and after.
The Linux archive retrieval matches its independent remote SHA-256.

Linux's actual hardened harness and sample suites pass 129 and 22 checks
without failures, errors or skips. Original XML and logs are retained.
The reviewed loading source keeps the serial library default, full shard
and global checks, exact failures and independent observations. Four
loading workers finish before the four native workers start. Lean sources
remain unchanged from the retained compiled runtime input. The build-file
difference from that runtime checkpoint changes only development suite
selection, following accepted PR52.

The helper is the previously reviewed capture driver with only its source
label updated. Both helpers and their original hash manifest are retained.
Project process observations found no co-runner before the phases; they do
not establish zero background CPU. Host load and complete storage and cache
qualifications remain in the original before/after records. File caches
were not flushed and residency is unknown. These observations establish
the timing target; they do not establish a causal speedup against older
sources or runtimes. The earlier 33.707907737-second Linux miss is unchanged.

The macOS GNU df observation identifies the sealed root snapshot. A separate
system-df and diskutil observation identifies writable APFS Data storage
**after the phase only**. Its device number matches the original storage
stat before and after. The original filesystem observations remain intact;
the later observation does not replace them. Linux records ordinary ext4
storage before and after.

`raw-sha256.json` binds all 34 original compressed artifacts. `acceptance.json`
records the two results. The read-only validator checks original bytes,
complete source and helper bindings, historical results, paths and limits.
Four independent mutations are refused after their file digests are
rebound: duplicate fixture paths, a false target flag, a changed library
identity and a changed selected name. No replay runs during these checks.
Independent evidence review and normal delivery remain required. T04c is
IN PROGRESS.

Run the bounded read-only check:

```sh
python3 -B reports/20261008-development-replay-parallel-acceptance/validate.py
```
