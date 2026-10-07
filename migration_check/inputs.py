"""Read and translate the actual schema and migration SQL once per command.

`verify`, `verify-bundle` and `prepare` all derive the generated Lean inputs the same
way, so a bundle is always checked against the SQL the verifier itself parsed.
"""

import argparse
from dataclasses import dataclass
import hashlib
from pathlib import Path

from .diagnostics import Rejection
from belay.sqlite.profiles import ExecutionProfile, profile
from .runtime import Runtime
from .lean_inputs import schema_inputs, sql_inputs
from belay.sqlite.structural import Json, generated_inputs_wire
from belay.sqlite.sql_tree import parse
from belay.sqlite.translate import starting_schema, statements


def read_sql(path: Path) -> bytes:
    """Bound input before allocation while preserving the exact bytes the parser checks."""
    with path.open("rb") as stream:
        sql = stream.read(1024 * 1024 + 1)
    if len(sql) > 1024 * 1024:
        raise Rejection("UNVERIFIED", "SQL exceeds the 1 MiB parser limit", source=str(path))
    return sql


@dataclass(frozen=True)
class GeneratedInputs:
    """Generated Lean sources and exact input identities for one request."""

    profile: ExecutionProfile
    schema_source: str
    sql_source: str
    schema_hash: str
    statements: int
    hashes: dict[str, str]
    structural: dict[str, Json]
    """The same request as `sql_source`, as the structural record the bundle checker decodes."""


def generated_inputs(options: argparse.Namespace) -> GeneratedInputs:
    """Parse schema and migration with the pinned frontend and emit the generated inputs."""
    selected = profile(options.profile)
    runtime = Runtime.locate(selected.engine)
    schema_bytes, migration_bytes = read_sql(options.schema), read_sql(options.migration)
    schema = starting_schema(parse(runtime.parser, schema_bytes, str(options.schema), selected.engine))
    script = statements(parse(runtime.parser, migration_bytes, str(options.migration), selected.engine))
    if not script:
        raise Rejection("INPUT_ERROR", "Migration must contain at least one statement", source=str(options.migration))
    schema_hash = hashlib.sha256(schema_bytes).hexdigest()
    hashes = {"schema.sql": schema_hash, "migration.sql": hashlib.sha256(migration_bytes).hexdigest(),
              "profile": selected.engine}
    # Lean emission calls the same frontend admission as native and model consumers.
    sql_source = sql_inputs(schema, script, selected)
    return GeneratedInputs(selected, schema_inputs(schema), sql_source, schema_hash, len(script), hashes,
                           generated_inputs_wire(schema, script, selected))
