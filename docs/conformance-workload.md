# Record an external workload

The workload commands record SQL under a measured execution profile, freeze the
observations, and replay them against native SQLite and the current model. Keep
a real workload's SQL, profile and results outside this repository. The neutral
inputs in [synthetic-workload](../conformance/synthetic-workload/workload.json)
exercise the same commands.

An inventory accounts for every `.sql` file under its input directory. Setup
files initialize the schema and fixture data. Each case is an independently
initialized sequence of application statements or migration statements. The
tool checks the supplied inventory; the workload owner still establishes that
it contains the application's complete SQL interface.

## Input directory

Create `workload.json` with this structure:

```json
{
  "workloadFormatVersion": 1,
  "profile": "profile.json",
  "setup": ["schema.sql"],
  "cases": [
    {
      "name": "read-by-id",
      "sql": "query.sql",
      "features": ["select", "typed-parameters"],
      "parameters": [[{"integer": {"value": 7}}]]
    }
  ]
}
```

`profile.json` is the complete profile record described in
[execution profiles](execution-profile.md), with measured engine identity.
Recording establishes and reads back its settings. A profile the recorder
cannot establish is refused.

Format-2 profiles can request actual read-only access, trusted schema and both
DQS settings. Read-only cases initialize fixture files using a separate writable
connection, commit and close it, then open the case read-only with the same
behavioral settings. A final intentional write denial records code 8; environmental
open, permissions, recovery, I/O and locking failures still fail recording.

Paths are relative to the input directory. Absolute paths, parent traversal and
symlinks outside that directory are refused. Every referenced SQL file has a
`.sql` extension. Every SQL file in the directory must be listed as setup or a
case. A file may be used by several cases with different parameter values.
Cases can add fixture files through an optional `setup` list, after the common
setup. Case names are unique.

`parameters` contains one array per statement, including `[]` for statements
without parameters. Cells use the native format: `"null"`, signed 64-bit
`integer.value`, IEEE-754 `real.bits` as a decimal string, or `text.bytes` and
`blob.bytes` as byte arrays. Optional `requirements` contains requirement IDs.
`features` supplies report categories.

A controlled-clock profile also requires `setupClockUnixMilliseconds` in the
inventory and `clockUnixMilliseconds` in each case. The latter has one integer
per statement. SQLite defaults, triggers and supplementary queries use those
same controlled inputs. An excluded-clock profile accepts no clock fields.

Recording stops at the first SQLite error. A failed final statement can be
recorded. Any remaining SQL, parameter occurrence or clock input makes the
inventory incomplete and recording is refused. Split an intentional failing
sequence into separate cases if later statements also need evidence.

## Commands

Run in the pinned development shell, with the conformance runtime built:

```sh
python -m conformance.workload record /path/to/input --output /path/to/frozen
python -m conformance.workload replay /path/to/input \
  --corpus /path/to/frozen --runtime-root build/conformance --output /path/to/replay.json
python -m conformance.workload progress /path/to/input \
  --corpus /path/to/frozen --generic /path/to/generic-corpus \
  --runtime-root build/conformance --output /path/to/combined.json
```

Choose a new output directory when recording. The frozen manifest binds every
source file, the ordered shard bytes, formats, profiles and case membership.
Replay refuses changed inventory, SQL, profile or shard content. It checks fresh
native observations before reporting model verdicts. The combined report binds
both corpus digests and counts both denominators.

The synthetic directory demonstrates the mechanism. Its success does not
complete the real workload gate in [ADR 0005](adr-0005-conformance-corpus-scale.md).
The `record_sql` Python primitive remains available for other fixture layouts
and acquisition inputs.
