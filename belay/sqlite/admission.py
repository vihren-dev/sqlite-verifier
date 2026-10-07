"""Apply the same schema and literal-write admission before any consumer executes a script."""

from .schema_translate import validate_migration
from .sql_admission import validate_writes
from .sql_model import Statement, Table


def admit(schema: tuple[Table, ...], script: tuple[Statement, ...]) -> None:
    """Reject inputs outside the modeled subset while retaining statement source coordinates."""
    validate_migration(schema, script)
    validate_writes(schema, script)
