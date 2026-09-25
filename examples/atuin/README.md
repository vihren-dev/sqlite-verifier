# Atuin shell-column pilot certificate

This bundle uses the unchanged migration from Atuin commit
`5b10eb09c664d316b7384210399b02e6127f4027` and the complete persisted schema captured
from its pinned SQLx runner. It is a proposed contract for owner review; a successful
proof check does not constitute that review or complete the Step 1 pilot acceptance.

The four represented tables retain all ten schema objects: history, SQLx metadata,
two statistics tables, three explicit indexes and three implicit constraint indexes.
Admission requires the exact six successful prior version/checksum records and a
pending shell migration. It includes empty and nonempty history, nullable TEXT
primary keys and distinct physical rowids. It does not claim all possible Atuin
installation schemas, concurrent writers or crash recovery.

The approved reader selects every old history field and physical rowid from actual
storage. The next reader also selects `shell`. The checked requirement preserves
the old projection exactly and requires actual NULL shell values for every old row.
Rollback errors retain the old view; committed errors satisfy the same extension
as success. Runner semantics separately retain old metadata and add the exact bound
target, with the `-1` timing sentinel when its post-commit update fails. Statistics
rows may change while their definitions and all other storage remain intact.

From the repository root, in the declared development environment:

```sh
bin/migration-check verify \
  --profile examples/atuin/profile.json \
  --schema examples/atuin/schema.sql \
  --requirements examples/atuin/approved/Requirements.lean \
  --interpretation examples/atuin/approved/Interpretation.lean \
  --migration examples/atuin/migration.sql \
  --next-interpretation examples/atuin/NextInterpretation.lean \
  --proofs examples/atuin/Proofs.lean --format json
```

`Proofs.migrationCorrect` quantifies all admitted histories and all modeled runner
outcomes. `AtuinWitness` establishes both empty and populated readiness;
`AtuinTraces` establishes populated committed-success and timing-failure traces.
Those concrete witnesses prevent impossible branch definitions from passing
unnoticed; they are not substitutes for the universal proof. Native correspondence
is documented separately in the capture and conformance reports.

`AtuinSchema` and `AtuinCatalog` are transitive approved inputs. They do not import
candidate or generated modules. The verifier seals SQL/profile data and independently
reconstructs the expected theorem. After owner review, an approved-source baseline
can retain these exact source/dependency hashes for subsequent migration checks.
