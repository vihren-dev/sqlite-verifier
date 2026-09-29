# ADR 0004 review corrections

Created 2026-09-29. Status: ACTIVE.

The W1–W2 prototype must retain the default pinned SQLite engine, configure and
verify DQS independently on every native connection, and independently check
translated metadata against native column and index inventories. A translator
mutation must fail closed. Native schema parsing must be reused until the schema
changes, including rollback, and benchmark cases must share one compiled runner.
The report must distinguish native acquisition from compiled classification.

Generated closed proof terms must be checked against the transported JSON after
elaboration. Conformance modules must not enter the production library import
closure. REAL fixtures must handle infinities and explicitly reflect SQLite's
NaN-to-NULL behavior. Existing authored fixtures and error evidence must survive.

Validation uses live pinned SQLite tests for connection policy, metadata mutations,
transactional schema rollback, exact special REAL storage, and stream parity;
Lean kernel checks for proof-term JSON identity; Nix source-identity and full
regression checks; and a fresh benchmark with stage timings. All checks are bounded
by the existing pytest/command timeouts.

Relevant files: conformance/native_connection.py, native_trace.py, model_check.py,
model_assertions.py, pipeline.py; SqliteVerifier/Conformance*.lean; lakefile.toml;
build-support/{sources,default,tests}.nix. SQLite deduplicates equivalent UNIQUE
indexes; integer primary keys need no index. Cache keys must reflect actual schema
content across visible and committed views. ADR status remains Proposed pending
an owner decision on the later pipeline; completed prototype is recorded separately.
