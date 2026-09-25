# Atuin business model and strict interpretation

Created: 2026-09-25. Status: DONE (bounded model/decoder component).
Task: [SQL-only core](20260925-sql-only-core.task.md), owner business-model correction.

Added approved HistoryModel and HistoryDecoding, plus finite HistoryDecodingChecks.
The model imports Std only and contains meaningful application UUID identity,
nanosecond timestamps/duration, exit status, command, location/session/origin,
author, optional intent/deletion/shell. It contains no SQL rows, physical rowids
or bookkeeping metadata. Source mapping is documented in the example README.

Direct pinned upstream source reads confirmed database.rs FromRow, HistoryId and
History fields, the HistoryFromDb builder, CmdOrigin, nanosecond conversion and
CLI duration recording. Sources were read individually from GitHub; no app repo,
application build or framework invocation was imported. Required values use a
strict UTF-8/int64/canonical lowercase UUID admission subset. Every row decodes
or the whole observation fails. Optional malformed stored values are excluded
explicitly, even where upstream would swallow a decode error. Author and intent
use Unicode White_Space emptiness while preserving nonblank text; shell is not
trimmed. Host-only origin and author fallback intentionally differ per source.

Six generic decoder lemmas establish signed numeric validity, decoded business
validity and unknown shell, row count, all-row validity, NULL shell attachment,
and preservation of business validity under shell attachment. Fourteen finite
kernel checks cover nonempty/empty views, optional data, Unicode, signed bounds,
malformed UUID/UTF-8/storage/missing cells, exact shell correspondence and no
silently filtered rows. The 20 named theorem audits use only propext,
Classical.choice and Quot.sound. No sorryAx or native_decide is used.

All three modules compiled using exact local copies and the checked read-only
formal core library. Each command had a 30-second timeout; final decoder/check
compilation took approximately 0.7/1.6 seconds. Lead independently source-reviewed
and compiled the modules in the complete typed proof bundle, and accepted them.
Root is integrating generated-schema anchoring separately. README describes the
business guarantee separately from stronger native/implementation storage facts;
proof bundle status stays pending until the complete checked handoff.

The separately delegated typed AtuinWitness candidate also compiled against the
live generated-schema mapping, with canonical UUIDs and actual business
observations. Lead copied and independently compiled it; final witness ownership
stays with lead, so it is excluded from this component's tracked diff. Earlier
NULL-ID positive witness work is superseded; NULL IDs are now a checked decoder
rejection. Exact candidate remains in build/sql-only-witness/TypedAtuinWitness.lean.
