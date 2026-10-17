# Initialize a required invoice priority

This example adds `priority INTEGER NOT NULL DEFAULT 7` to an existing invoice
table. Its contract requires that exact column metadata and preserves every
invoice rowid and amount. The proof covers all admitted starting tables,
including empty and populated tables. It requires successful execution.

The contract does not constrain which priority values a later application may
write. The model tests separately compare the initialized values with native
SQLite. `Proofs.lean` establishes this migration's complete generated target.

`belay.toml` names the contract, migration and proofs project. Use the ordinary
`prepare` and `verify-bundle` workflow described in the repository's data-path
documentation. Changing `DEFAULT 7` to `DEFAULT 8` invalidates the certificate.

