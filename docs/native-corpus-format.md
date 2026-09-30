# Native corpus records

`conformance.native_record.record_sql` records SQLite 3.51.0 before frontend
admission. `nativeVersion: 1` retains setup SQL, migration SQL, engine identity,
requirements, an initial snapshot and per-statement native events. SQLite's
prepare tail splits statements, including whole trigger definitions. Each event
retains result rows, primary/extended code, diagnostics, visible/committed
snapshots and transaction state. Execution stops on its first SQL error.

Snapshots contain all main-schema SQL objects, including views and triggers;
`table_xinfo`, `index_list`, `index_xinfo`, foreign-key metadata, and typed rows.
WITHOUT ROWID tables use their ordered primary key. Ordinary tables use an
unshadowed rowid alias; views and tables with all rowid aliases shadowed use a
sorted full-row multiset. Column-bounded reads support wide tables. Acquisition
never invokes the production parser or translator.

This is a single-main-database profile. Attached and temporary schemas are
explicit excluded connection contexts, not silently missing observations.
Unobservable views or absent application callbacks are acquisition failures.

`native_replay.prepare` derives schema and statements using today's frontend on
every replay. Unsupported cases retain their original native record. Admitted
cases cross-check the frozen PRAGMA metadata independently and reach the existing
Lean classifier. No native trace is regenerated or edited during model replay.
The structural case format remains [version one](conformance-format-v1.md).
