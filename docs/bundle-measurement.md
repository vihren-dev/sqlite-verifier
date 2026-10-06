# Run a retained cold-pair campaign

This guide is for the team that collects T06 evidence. The named launcher and
writer have bounded configuration and synthetic persistence checks. The final
T05/documentation installed runtime and integrated gates are not accepted yet.
Actual campaigns wait for that runtime and coordinated idle macOS/Linux hosts.
Synthetic test intervals are not performance evidence.

Run the launcher from the source checkout that contains the measurement tools.
Supply the selected installed runtime, its declared executable Python, a new
output directory and one positive integer timeout in seconds. Read the Python
path from the selected runtime's `python-path`; the launcher refuses another
interpreter. The output's parent directory must exist. The output itself must
not exist and must be outside the runtime and source inputs.

After the runtime and hosts are ready, use explicit selections such as:

```sh
V=/absolute/path/to/accepted-installation
P=/absolute/path/declared/in/that-installation/python-path
O=/absolute/path/to/existing-evidence-parent
T=WHOLE_PATH_TIMEOUT_SECONDS
"$P" -m tools.bundle_measurement --case small-success \
  --runtime "$V" --python "$P" --output "$O/small-success-new" --timeout-seconds "$T"
"$P" -m tools.bundle_measurement --case checked-refutation \
  --runtime "$V" --python "$P" --output "$O/checked-refutation-new" --timeout-seconds "$T"
"$P" -m tools.bundle_measurement --case atuin \
  --runtime "$V" --python "$P" --output "$O/atuin-new" --timeout-seconds "$T"
```

Replace `WHOLE_PATH_TIMEOUT_SECONDS` with the coordinated common path deadline.
The same timeout applies to `verify` and the entire preparation/checking path.
Installation and dependency downloads occur before the campaign. The launcher
does not choose a slowdown percentage or time tolerance.

The named cases select shipped sources from the same runtime:

| Case | Approved sources | Candidate sources | Profile | Expected final status |
|---|---|---|---|---|
| `small-success` | `examples/approved` | `examples/add_column_then_table` | `3.51.0` | `VERIFIED` |
| `checked-refutation` | `examples/approved` | `examples/missing_required_column` | `3.51.0` | `VIOLATED` |
| `atuin` | `examples/atuin/approved` | `examples/atuin` | `3.46.0` | `VERIFIED` |

The small cases use `examples/approved/schema.sql`. Atuin uses
`examples/atuin/schema.sql`. The recorded roots include each full Lean source
directory, so sibling dependencies remain part of the input identity. Every
role argument is an absolute path. The common arguments match the existing
[installation commands](install.md) and [data path](data-path.md).
`TrialSpec` in `tools/bundle_measurement_paths.py` remains available for custom
input roots and manual argument tuples.

For each pair, the writer creates fresh `verify` and `bundle` directories. It
alternates which path runs first. The bundle path runs `prepare`, retains
`proof.ndjson`, and passes that exact file to `verify-bundle`. Preparation must
return `PREPARED` with exit 0. Positive checks must return `VERIFIED` with exit 0;
checked refutation must return `VIOLATED` with public CLI exit 1 and independently
observed checker exit 2. Both paths share the protected role arguments.

The campaign keeps `campaign.json`, `summary.json`, `identity.json.gz` and every
`pair-NN` directory. Raw streams, commands, identities, stage spans and artifact
records stay with each path. Invalid or interrupted pairs remain available. The
writer never overwrites a prior campaign. A missing selected input is refused
before evidence creation; runtime byte hashing and actual command checks still
determine whether a complete installation can execute the configured request.

A complete nine-pair look extends the same run to 25 only when the predeclared
confidence rule requires it. Exit 0 means the campaign completed acquisition;
it does not mean cutover is approved. A retained invalid summary returns exit 1,
and configuration/output errors return exit 2. Each result requires owner review.
A regression needs an owner decision; an unresolved interval prevents cutover.
