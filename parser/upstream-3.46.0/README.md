# SQLite 3.46.0 upstream sources

Files are unmodified upstream copies, with their original public-domain notices.
`sha256.json` binds every incorporated file and is checked on every build.

Release source id:
`96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e`

`parse.y`, `lemon.c`, and `lempar.c` come from:
https://sqlite.org/2024/sqlite-src-3460000.zip

Archive SHA-256:
`070362109beb6899f65797571b98b8824c8f437f5b2926f88ee068d98ef368ec`

`sqlite3.c` and `sqlite3.h` come from:
https://sqlite.org/2024/sqlite-autoconf-3460000.tar.gz

Archive SHA-256:
`6f8e6a7b335273748816f9b3b62bbdc372a889de8782d7f048c653a447417a7d`

The downloaded amalgamation's SHA3-256 is
`094429ea827fcd32275e767134bc6c7b9ea394a2c5a9e653dd0a0690b2c11358`,
matching the official release log: https://sqlite.org/releaselog/3_46_0.html

This release matches Atuin's bundled SQLx engine. The syntax-only parser replaces
grammar actions with generic CST construction, as for the existing 3.51 parser.
Its grammar and token map are separately regenerated from these pinned sources.
The native CLI is an independent engine check; the SQLx capture records the
application runner's actual compile options and connection configuration.
