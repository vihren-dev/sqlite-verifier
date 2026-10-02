"""Count demonstrated scenarios against the fixed inventory without claiming requirement proof."""

from collections import Counter
from typing import cast

from conformance.case_format import Json


def inventory_rows(inventory: dict[str, Json]) -> list[dict[str, Json]]:
    """Keep the release inventory's order and reject an inconsistent denominator."""
    rows = cast(list[dict[str, Json]], inventory["requirements"])
    identities = [row["id"] for row in rows]
    if (type(inventory["count"]) is not int or inventory["count"] != len(rows)
            or any(not isinstance(identity, str) or not identity for identity in identities)
            or len(set(identities)) != len(rows)):
        raise ValueError("Requirement inventory count or identities mismatch")
    return rows


def reference_matches(tag: Json, identities: list[str]) -> list[str]:
    """Resolve citations against this release while refusing malformed reference values."""
    if not isinstance(tag, str) or not tag:
        raise ValueError(f"Unknown or ambiguous requirement tag: {tag}")
    return [identity for identity in identities if identity.startswith(tag)]


def credited_upstream(records: list[dict[str, Json]], inventory: dict[str, Json]) -> list[dict[str, Json]]:
    """Keep obsolete upstream citations as provenance without crediting a current requirement."""
    identities = [cast(str, row["id"]) for row in inventory_rows(inventory)]
    result: list[dict[str, Json]] = []
    for record in records:
        credited: list[Json] = []
        uncredited: list[Json] = []
        for tag in record["requirements"]:
            (credited if len(reference_matches(tag, identities)) == 1 else uncredited).append(tag)
        result.append({**record, "requirements": credited,
            **({"upstream": {**record["upstream"], "uncreditedRequirements": uncredited}}
               if uncredited else {})})
    return result


def resolved_ids(records: list[dict[str, Json]], inventory: dict[str, Json]) -> list[set[str]]:
    """Resolve short or full IDs once per case, so aliases cannot inflate scenario counts."""
    identities = [cast(str, row["id"]) for row in inventory_rows(inventory)]
    resolutions: dict[str, str] = {}
    cases: list[set[str]] = []
    for record in records:
        resolved: set[str] = set()
        for tag in cast(list[str], record["requirements"]):
            if not isinstance(tag, str) or not tag:
                raise ValueError(f"Unknown or ambiguous requirement tag: {tag}")
            if tag not in resolutions:
                matches = reference_matches(tag, identities)
                if len(matches) != 1:
                    raise ValueError(f"Unknown or ambiguous requirement tag: {tag}")
                resolutions[tag] = matches[0]
            resolved.add(resolutions[tag])
        cases.append(resolved)
    return cases


def comparison(before: list[dict[str, Json]], after: list[dict[str, Json]],
               inventory: dict[str, Json]) -> dict[str, Json]:
    """Use one inventory for both memberships, retaining every row including zero counts."""
    before_counts = Counter(identity for case in resolved_ids(before, inventory) for identity in case)
    after_counts = Counter(identity for case in resolved_ids(after, inventory) for identity in case)
    rows: list[Json] = [{"id": row["id"], "file": row["file"],
                        "publicTclEvidence": row["publicTclEvidence"],
                        "beforeCases": before_counts[row["id"]],
                        "afterCases": after_counts[row["id"]]}
                       for row in inventory_rows(inventory)]
    return {"inventoryCount": inventory["count"], "rows": rows,
            "beforeDenominator": len(before), "afterDenominator": len(after),
            "beforeRowsWithCases": len(before_counts), "afterRowsWithCases": len(after_counts),
            "rowsGainingCases": len(after_counts.keys() - before_counts.keys()),
            "rowsLosingCases": len(before_counts.keys() - after_counts.keys())}
