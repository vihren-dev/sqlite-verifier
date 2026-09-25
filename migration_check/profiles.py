"""Validate explicit engine/runner inputs and emit only fixed typed profile constructors."""

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Literal

from .diagnostics import Rejection

SQLX_KIND = "sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1"


def lean_bytes(value: bytes) -> str:
    """Bind exact UTF-8 or digest bytes without embedding executable Lean syntax."""
    return "[" + ", ".join(map(str, value)) + "]"


@dataclass(frozen=True)
class MigrationIdentity:
    """An approved previously applied version and exact SHA-384 checksum."""

    version: int
    checksum: bytes

    def lean(self) -> str:
        """Emit the formal catalog entry as a named record."""
        return f"{{ version := ({self.version}), checksum := {lean_bytes(self.checksum)} }}"


@dataclass(frozen=True)
class ExecutionProfile:
    """One supported fixed execution policy, with optional SQLx catalog parameters."""

    engine: Literal["3.51.0", "3.46.0"] = "3.51.0"
    migration_version: int = 0
    description: bytes = b""
    previous: tuple[MigrationIdentity, ...] = ()
    source_digest: str = ""

    def lean(self, migration: bytes | None) -> str:
        """Compute the target checksum from actual SQL, never from a manifest assertion."""
        if self.engine == "3.51.0":
            return ".sqlite351Autocommit"
        if migration is None:
            raise ValueError("The SQLx profile requires the original migration bytes")
        checksum = lean_bytes(hashlib.sha384(migration).digest())
        previous = "[" + ", ".join(entry.lean() for entry in self.previous) + "]"
        return (f".sqlite346Sqlx {{ migration := {{ version := ({self.migration_version}), "
                f"description := {lean_bytes(self.description)}, checksum := {checksum} }}, "
                f"previous := {previous} }}")


LEGACY_PROFILE = ExecutionProfile()


def object_fields(value: object, keys: set[str]) -> dict[str, object]:
    """Reject omitted and unknown fields at every manifest object boundary."""
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError(f"Profile object requires exactly these fields: {', '.join(sorted(keys))}")
    return value


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    """JSON duplicate keys must not let a reviewed value be replaced silently."""
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate profile field: {key}")
        result[key] = value
    return result


def version_number(value: object) -> int:
    """SQLx binds signed SQLite int64 versions; booleans are not version numbers."""
    if type(value) is not int or not -(2 ** 63) <= value < 2 ** 63:
        raise ValueError("Migration versions must be signed 64-bit integers")
    return value


def profile(specification: str) -> ExecutionProfile:
    """Preserve the legacy version input and admit only the exact supported runner manifest."""
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", specification):
        if specification == "3.51.0":
            return LEGACY_PROFILE
        raise Rejection("UNSUPPORTED", f"Requested SQLite {specification}; use a supported exact execution profile")
    path = Path(specification)
    if not path.is_file():
        raise Rejection("INPUT_ERROR", "Profile must be SQLite 3.51.0 or an existing execution-profile JSON file")
    try:
        with path.open('rb') as stream:
            source = stream.read(1024 * 1024 + 1)
        if len(source) > 1024 * 1024:
            raise ValueError("Execution profile exceeds 1 MiB")
        data = object_fields(json.loads(source, object_pairs_hook=unique_object), {'kind', 'migration', 'previous'})
        if data['kind'] != SQLX_KIND:
            raise Rejection("UNSUPPORTED", "Unsupported execution-profile kind")
        target = object_fields(data['migration'], {'version', 'description'})
        version = version_number(target['version'])
        description = target['description']
        if not isinstance(description, str):
            raise ValueError("Migration description must be a string")
        prior = data['previous']
        if not isinstance(prior, list):
            raise ValueError("Previous migrations must be an ordered array")
        entries: list[MigrationIdentity] = []
        for item in prior:
            entry = object_fields(item, {'version', 'checksum'})
            number = version_number(entry['version'])
            checksum = entry['checksum']
            if not isinstance(checksum, str) or re.fullmatch(r'[0-9a-fA-F]{96}', checksum) is None:
                raise ValueError("Previous checksums must contain exactly 48 hexadecimal bytes")
            if number >= version or (entries and number <= entries[-1].version):
                raise ValueError("Previous versions must strictly increase and precede the target")
            entries.append(MigrationIdentity(number, bytes.fromhex(checksum)))
        return ExecutionProfile('3.46.0', version, description.encode('utf-8'), tuple(entries),
                                hashlib.sha256(source).hexdigest())
    except (ValueError, UnicodeError, RecursionError) as error:
        raise Rejection("INPUT_ERROR", str(error), source=str(path)) from error
