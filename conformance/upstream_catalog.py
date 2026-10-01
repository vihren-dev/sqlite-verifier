"""Fixed ADR 0005 source categories and file exclusions for the v4 freeze."""

from fnmatch import fnmatchcase

from conformance.case_format import Json

HISTORICAL_FILES: tuple[str, ...] = tuple("""alter.test alter2.test alter3.test alter4.test alterauth.test
alterauth2.test altercol.test altercorrupt.test alterdropcol.test alterdropcol2.test
alterfault.test alterlegacy.test altermalloc.test altermalloc2.test altermalloc3.test
alterqf.test altertab.test altertab2.test altertab3.test altertrig.test e_blobbytes.test
e_blobclose.test e_blobopen.test e_blobwrite.test e_changes.test e_createtable.test
e_delete.test e_droptrigger.test e_dropview.test e_expr.test e_fkey.test e_fts3.test
e_insert.test e_reindex.test e_resolve.test e_select.test e_select2.test
e_totalchanges.test e_update.test e_uri.test e_vacuum.test e_wal.test e_walauto.test
e_walckpt.test e_walhook.test""".split())
ADDITIONAL_FILES: tuple[str, ...] = ("trigger2.test", "check.test", "func.test", "cast.test", "returning1.test",
                    "upsert1.test", "date.test", "json101.test", "index.test", "expr.test")

FILE_EXCLUSIONS: tuple[tuple[str, str], ...] = (
    ("*fault*", "fault injection"), ("*malloc*", "allocation fault injection"),
    ("*corrupt*", "database corruption"), ("*auth*", "authorizer context"),
    ("*qf*", "query-plan context"), ("e_blob*.test", "incremental BLOB-handle operations"),
    ("incrblob*.test", "incremental BLOB-handle operations"),
    ("wal*.test", "WAL context"), ("e_wal*.test", "WAL context"),
    ("uri*.test", "URI context"), ("e_uri*.test", "URI context"),
    ("fts*.test", "FTS context"), ("e_fts*.test", "FTS context"),
)
SOURCE_FEATURES: dict[str, tuple[str, ...]] = {
    "e_changes.test": ("direct-counts", "triggers", "foreign-key"),
    "e_createtable.test": ("schema", "text-primary-key", "defaults", "check"),
    "e_delete.test": ("delete", "foreign-key-cascade"),
    "e_droptrigger.test": ("schema", "triggers"), "e_dropview.test": ("schema", "views"),
    "e_expr.test": ("expressions", "cast", "real-arithmetic"),
    "e_fkey.test": ("foreign-key", "foreign-key-cascade", "transaction"),
    "e_insert.test": ("insert", "defaults"), "e_reindex.test": ("indexes",),
    "e_resolve.test": ("name-resolution",),
    "e_select.test": ("select", "join", "order-by", "limit", "offset", "group-by", "aggregates"),
    "e_select2.test": ("select", "join", "order-by", "limit", "offset", "group-by", "aggregates"),
    "e_totalchanges.test": ("direct-counts",), "e_update.test": ("update", "on-conflict"),
    "e_vacuum.test": ("vacuum",),
    "trigger2.test": ("triggers", "transaction"), "check.test": ("check", "constraint-failure", "coalesce"),
    "func.test": ("coalesce", "count", "sum", "avg", "max"),
    "cast.test": ("cast", "storage-classes", "numeric-edges"),
    "returning1.test": ("returning", "defaults", "on-conflict", "indexes"),
    "upsert1.test": ("on-conflict",), "date.test": ("controlled-clock", "strftime"),
    "json101.test": ("json_extract", "json_each"), "index.test": ("indexes",),
    "expr.test": ("expressions", "real-arithmetic", "coalesce", "cast"),
}


def catalog_patterns() -> tuple[str, ...]:
    """Return exact filenames rather than globs that could silently grow membership."""
    return tuple(sorted(HISTORICAL_FILES + ADDITIONAL_FILES))


def file_exclusion_reasons(filename: str) -> list[str]:
    """Keep every applicable file reason, including overlapping fault and feature contexts."""
    return sorted({reason for pattern, reason in FILE_EXCLUSIONS if fnmatchcase(filename, pattern)})


def source_features(filename: str) -> list[str]:
    """Describe reviewed source categories; these are provenance, not per-case coverage claims."""
    return list(SOURCE_FEATURES.get(filename, ("schema", "alter-table") if filename.startswith("alter") else ()))


def source_catalog() -> list[dict[str, Json]]:
    """Expose the fixed 55 sources, including the 18 excluded entries, for freeze manifests."""
    return [{"file": filename, "features": source_features(filename),
             "fileExclusions": file_exclusion_reasons(filename)} for filename in catalog_patterns()]


def exclusion_policy() -> list[dict[str, Json]]:
    """Record the actual filename matching rules alongside their explanations."""
    return [{"pattern": pattern, "reason": reason} for pattern, reason in FILE_EXCLUSIONS]
