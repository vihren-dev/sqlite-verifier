# SQLite profile input

`--profile` selects a supported pinned SQLite release: `3.51.0` or `3.46.0`.
It selects the matching grammar and binds the version to the checked theorem.
Unsupported versions return `UNSUPPORTED`; malformed versions and the retired
framework JSON manifests return `INPUT_ERROR`.

Profiles contain only SQLite semantic settings. Supported settings are fixed
and documented in [execution profiles](execution-profile.md). Migration identities,
checksums, prior migration records and application data assumptions are not
profile fields. They belong in ordinary SQL and approved Lean requirements or
interpretations, according to whether they describe operations or state facts.

`SchemaInputs.lean` binds the parsed starting schema and is available to approved
interpretations. `SqlInputs.lean` imports it and binds the script, resulting schema
and SQLite profile. The independent gate reconstructs the expected theorem from those
sealed inputs. A profile never inserts statements, wraps a transaction or updates
bookkeeping. Explicit transaction control in a migration is ordinary SQL.

The [Atuin example](../examples/atuin/README.md) illustrates this interface with
source-linked SQL and application assumptions. The verifier does not invoke an
ORM, inspect an application checkout, or certify a framework invocation.
