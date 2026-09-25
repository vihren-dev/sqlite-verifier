> Historical candidate research. The owner's SQL-only correction supersedes
> the capture and framework-integration recommendations below. Current scope is
> the [SQL-only core task](../plans/20260925-sql-only-core.task.md) and the
> [source-linked Atuin example](../examples/atuin/README.md).

# Open-source pilot candidates

Research date: 2026-09-25. Status: Atuin selected; verification and acceptance pending.
The owner requested a popular GitHub project with SQLite, migrations, exportable
SQL and schema, and a manageable logical model. Star counts are observations from
GitHub's API on that date, not quality or compatibility guarantees.

## Recommendation: Atuin's local history database

[Atuin](https://github.com/atuinsh/atuin) has 31,800 stars and an MIT license.
Inspect revision `5b10eb09c664d316b7384210399b02e6127f4027`. Its history database
uses SQLite and committed SQL migration files; migration bodies require no ORM
translation. The proposed first case is
[20260709214605_shell.sql](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260709214605_shell.sql):

```sql
alter table history add column shell text;
```

The proposed logical requirement is preservation of every existing history row,
its physical identity, and all old stored fields, while adding the nullable
`shell` field with NULL for pre-existing rows. This is a proposed contract for
owner review, not an approved application requirement. The earlier
[author/intent migration](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20260224000100_history_author_intent.sql)
provides a subsequent two-statement case.

An actual scratch experiment used the six preceding unchanged migration files
with our pinned SQLite 3.51.0 and exported the resulting application schema.
It contains one history table and three explicit indexes. The production
translator admits the exact shell-addition statement but rejects the untouched
starting schema at its UNIQUE constraint (bytes 263–299 in that export).
This experiment excludes SQLx's bookkeeping table and is not a full application
installation or completed pilot. Its temporary evidence is in
`/tmp/sqlite-verifier-atuin-research-20260925` on the research host.

The [initial schema](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/migrations/20210422143411_create_history.sql)
has a text primary key, NOT NULL fields, a composite UNIQUE constraint and
indexes. None is admitted by our current full-schema subset. A text primary key
is not SQLite's INTEGER rowid alias and does not alone exclude NULL; retain rowid
and stored ID separately unless the owner approves a stronger validity invariant.
See [SQLite's primary-key rules](https://sqlite.org/lang_createtable.html#the_primary_key).

Before implementation, capture the complete database, including
`_sqlx_migrations`, and pin the runner's transactions, bookkeeping, configuration
and SQLite version. Atuin invokes SQLx through its
[migration wrapper](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-common/src/db/mod.rs).
The [history implementation](https://github.com/atuinsh/atuin/blob/5b10eb09c664d316b7384210399b02e6127f4027/crates/atuin-client/src/database.rs)
describes history as a cache of separately encrypted records. This pilot would
address history-database migration guarantees, not sync, encryption, or whole-app
correctness. The lead independently reviewed this recommendation and its limits.

## Alternatives

| Project | Popularity | Concrete case and export | Assessment |
| --- | --- | --- | --- |
| [Healthchecks](https://github.com/healthchecks/healthchecks) | 10,362 stars | Django migrations [0084](https://github.com/healthchecks/healthchecks/blob/master/hc/api/migrations/0084_ping_body_raw.py) and [0085](https://github.com/healthchecks/healthchecks/blob/master/hc/api/migrations/0085_ping_object_size.py) add nullable binary/integer ping fields. `manage.py sqlmigrate` exports each migration. | Best Django alternative. Preserve ping identity, check association and old fields. Existing constraints, indexes, type spellings and transaction wrappers need support. |
| [Mealie](https://github.com/mealie-recipes/mealie) | 13,310 stars | [Revision b3f1c9a27d84](https://github.com/mealie-recipes/mealie/blob/8399b0f2b5760d3d8b8441e234724afce6dcafe5/mealie/alembic/versions/2026-08-25-09.00.00_b3f1c9a27d84_add_external_avatar_hash_to_users.py) adds a nullable avatar hash. Its Alembic environment supports offline `upgrade START:END --sql`. | Real SQL export, but larger relational schema. Some migrations require reflection/data access; full-history offline export is not assured. |
| [Navidrome](https://github.com/navidrome/navidrome) | 23,780 stars | Goose uses SQL files and Go migrations; [rated_at addition](https://github.com/navidrome/navidrome/blob/3f89baaec8f3285429496d5f0b796165034c70ed/db/migrations/20251109010105_add_annotation_rating_date.sql) is already SQL. | Useful later; no documented generic exporter identified for arbitrary Go migrations. More schema and runner complexity than Atuin. |
| [Linkding](https://github.com/sissbruecker/linkding) | 11,227 stars | Django `sqlmigrate`; [notes migration](https://github.com/sissbruecker/linkding/blob/27b7303baf41bb28babc610ac8eaa486e1ddfab5/bookmarks/migrations/0022_bookmark_notes.py). | Appealing domain, but notes uses `blank=True`, not `null=True`; SQLite table reconstruction is required. Later URL changes involve indexes and population. |

The Django/Alembic commands were verified in source/documentation, not executed
in application environments. SQLite support is explicit in
[Healthchecks settings](https://github.com/healthchecks/healthchecks/blob/master/hc/settings.py)
and [Mealie's SQLite installation guide](https://mealie.io/documentation/getting-started/installation/sqlite/).
[Mealie's Alembic environment](https://github.com/mealie-recipes/mealie/blob/8399b0f2b5760d3d8b8441e234724afce6dcafe5/mealie/alembic/env.py)
provides its offline SQL-export path.

## Export and acceptance boundary

For a complete starting database, export its actual schema with the standard
SQLite CLI, preserving constraints and relevant objects:

```sh
sqlite3 -init /dev/null -readonly DATABASE '.schema' > before.sql
```

[SQLite documents `.schema`](https://sqlite.org/cli.html#querying_the_database_schema).
For Atuin, the pinned migration file itself is the SQL sequence. For Django,
[sqlmigrate](https://docs.djangoproject.com/en/6.0/ref/django-admin/#sqlmigrate)
emits SQL for one migration against the configured database. Alembic's
[offline mode](https://alembic.sqlalchemy.org/en/latest/offline.html) emits SQL,
with [extra limits for SQLite batch rebuilding](https://alembic.sqlalchemy.org/en/latest/batch.html#working-in-offline-mode).

None of the inspected complete starting schemas was accepted by the initial
[semantic subset](semantic-subset.md). Constraints, indexes and runner behavior
must not be discarded to make an example pass. Selecting Atuin and defining the
required compatibility extension was authorized by the owner on 2026-09-25.
The [implementation task](../plans/20260925-atuin-shell-migration.task.md) now
tracks that work. The research itself did not alter the semantic model,
execution profile, roadmap or approved baseline.
A real case study also does not imply adoption or endorsement by upstream
maintainers. Human authoring/review effort and owner acceptance remain necessary.
