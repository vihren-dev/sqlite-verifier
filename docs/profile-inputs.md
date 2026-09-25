# Execution-profile input

The `--profile` input selects both the native grammar and the formal execution
policy. `--profile 3.51.0` preserves the original SQLite autocommit workflow.
A bare `3.46.0` does not select a runner implicitly.

For the supported SQLx policy, pass a JSON file as the same input:

```json
{
  "kind": "sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1",
  "migration": {"version": 20, "description": "new column"},
  "previous": []
}
```

The fixed kind identifies the pinned engine and runner configuration; it is not
an arbitrary configuration override. Unknown fields or kinds reject. Previous
migrations are listed in strictly increasing order, all before the target:

```json
{"version": 10, "checksum": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
```

Each prior checksum is exactly 48 bytes written in hexadecimal. Versions are
signed 64-bit integers. Duplicate fields, duplicate/out-of-order versions and
malformed values reject. The target description is bound as its exact UTF-8
bytes. The verifier computes the target SHA-384 checksum from the unchanged SQL
input bytes; the manifest cannot supply a replacement checksum.

`SqlInputs.lean` seals the selected profile and catalog together with the parsed
schemas and script. The independent gate reconstructs the target using that
sealed profile. `inputs.json` records the exact profile-file SHA-256 for inspection;
that export does not approve application requirements or prior catalog contents.
The proof must establish the profile's readiness and all modeled outcomes.

This mode checks one pending final migration after the listed successful prior
migrations. Its payload contains only plain nullable, default-free ADD COLUMN
statements outside the bookkeeping table. CREATE and an exact leading
`-- no-transaction` byte prefix reject as unsupported. The prefix check follows
SQLx exactly, without trimming whitespace or changing case. Out-of-order pending
migrations and changed engine/runner configurations are outside this mode. The actual supported execution boundary and
its native correspondence evidence are described in the execution-profile and
pilot documentation.
