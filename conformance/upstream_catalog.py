"""Pinned feature families, explicit source labels and file exclusions for the v5 freeze."""

from fnmatch import fnmatchcase
from pathlib import Path

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
CATALOG_VERSION = 2
FAMILY_PATTERNS: tuple[str, ...] = (
    'trigger*.test',
    'fkey*.test',
    'select*.test',
    'agg*.test',
    'count*.test',
    'minmax*.test',
    'groupby*.test',
    'distinctagg*.test',
    'date*.test',
    'json*.test',
    'cast.test',
    'returning*.test',
    'upsert*.test',
    'trans*.test',
    'insert*.test',
    'update*.test',
    'delete*.test',
    'expr*.test',
    'func*.test',
    'check*.test',
    'index*.test',
)
ADDITIONAL_FILES: tuple[str, ...] = tuple("""aggerror.test aggfault.test aggnested.test aggorderby.test cast.test check.test
checkfault.test count.test countofview.test date.test date2.test date3.test
date4.test date5.test delete.test delete2.test delete3.test delete4.test
delete_db.test distinctagg.test expr.test expr2.test exprfault.test exprfault2.test
fkey1.test fkey2.test fkey3.test fkey4.test fkey5.test fkey6.test
fkey7.test fkey8.test fkey_malloc.test func.test func2.test func3.test
func4.test func5.test func6.test func7.test func8.test func9.test
index.test index2.test index3.test index4.test index5.test index6.test
index7.test index8.test index9.test indexA.test indexedby.test indexexpr1.test
indexexpr2.test indexexpr3.test indexfault.test insert.test insert2.test insert3.test
insert4.test insert5.test insertfault.test json101.test json102.test json103.test
json104.test json105.test json106.test json107.test json108.test json501.test
json502.test jsonb01.test minmax.test minmax2.test minmax3.test minmax4.test
returning1.test returningfault.test select1.test select2.test select3.test select4.test
select5.test select6.test select7.test select8.test select9.test selectA.test
selectB.test selectC.test selectD.test selectE.test selectF.test selectG.test
selectH.test trans.test trans2.test trans3.test transitive1.test trigger1.test
trigger2.test trigger3.test trigger4.test trigger5.test trigger6.test trigger7.test
trigger8.test trigger9.test triggerA.test triggerB.test triggerC.test triggerD.test
triggerE.test triggerF.test triggerG.test triggerupfrom.test update.test update2.test
upsert1.test upsert2.test upsert3.test upsert4.test upsert5.test upsertfault.test""".split())

FILE_EXCLUSIONS: tuple[tuple[str, str], ...] = (
    ("delete_db.test", "file-level database deletion"),
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
    return tuple(sorted(set(HISTORICAL_FILES + ADDITIONAL_FILES)))


def file_exclusion_reasons(filename: str) -> list[str]:
    """Keep every applicable file reason, including overlapping fault and feature contexts."""
    return sorted({reason for pattern, reason in FILE_EXCLUSIONS if fnmatchcase(filename, pattern)})


def source_features(filename: str) -> list[str]:
    """Describe reviewed source categories; these are provenance, not per-case coverage claims."""
    if filename in SOURCE_FEATURES:
        return list(SOURCE_FEATURES[filename])
    for pattern, labels in (
        ("alter*", ("schema", "alter-table")), ("trigger*", ("triggers",)),
        ("fkey*", ("foreign-key",)), ("select*", ("select",)),
        ("agg*", ("aggregates",)), ("count*", ("count",)), ("minmax*", ("min", "max")),
        ("distinctagg*", ("aggregates", "distinct")), ("date*", ("date-time",)),
        ("json*", ("json",)), ("returning*", ("returning",)), ("upsert*", ("on-conflict",)),
        ("trans*", ("transaction",)), ("insert*", ("insert",)), ("update*", ("update",)),
        ("delete*", ("delete",)), ("expr*", ("expressions",)), ("func*", ("functions",)),
        ("check*", ("check",)), ("index*", ("indexes",)),
    ):
        if fnmatchcase(filename, pattern):
            return list(labels)
    return []


def source_catalog() -> list[dict[str, Json]]:
    """Expose every pinned family source and its provenance labels for freeze manifests."""
    return [{"file": filename, "features": source_features(filename),
             "fileExclusions": file_exclusion_reasons(filename)} for filename in catalog_patterns()]


def exclusion_policy() -> list[dict[str, Json]]:
    """Record the actual filename matching rules alongside their explanations."""
    return [{"pattern": pattern, "reason": reason} for pattern, reason in FILE_EXCLUSIONS]


def family_policy() -> dict[str, Json]:
    """Bind the whole-family selection rule separately from the frozen exact file names."""
    return {"version": 1, "patterns": list(FAMILY_PATTERNS)}


def validate_source_files(upstream: Path) -> None:
    """Refuse a catalog that omits a pinned family member or names an absent source file."""
    sources = upstream / "test"
    expected = set(HISTORICAL_FILES) | {path.name for pattern in FAMILY_PATTERNS for path in sources.glob(pattern)}
    if (set(catalog_patterns()) != expected
            or any(not (sources / filename).is_file() for filename in expected)):
        raise ValueError("Upstream catalog differs from the pinned feature families")
