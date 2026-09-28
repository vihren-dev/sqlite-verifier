"""Describe pytest's selected items using collected metadata, without running fixtures."""

import inspect
from typing import TypedDict

import pytest

LEVELS = {"unit", "integration", "e2e"}
CONCERNS = {"parser", "kernel", "approval", "atuin", "packaging", "conformance", "environment"}
RESOURCES = {"requires_lean", "requires_native", "requires_nix", "requires_sandbox"}


class CaseDescription(TypedDict):
    """Stable public catalogue fields also embedded in execution reports."""

    node_id: str
    description: str
    parameter_id: str | None
    level: str
    concerns: list[str]
    resources: list[str]


def describe_cases(items: list[pytest.Item]) -> list[CaseDescription]:
    """Reject ambiguous identities and missing metadata before any test can run."""
    descriptions: list[CaseDescription] = []
    seen: set[str] = set()
    for item in items:
        if item.nodeid in seen:
            raise pytest.UsageError(f"Duplicate test node ID: {item.nodeid}")
        seen.add(item.nodeid)
        if not isinstance(item, pytest.Function):
            raise pytest.UsageError(f"Unsupported test item: {item.nodeid}")
        doc = inspect.getdoc(item.obj)
        if not doc:
            raise pytest.UsageError(f"Missing scenario description: {item.nodeid}")
        markers = {marker.name for marker in item.iter_markers()}
        levels = markers & LEVELS
        if len(levels) != 1:
            raise pytest.UsageError(f"Expected exactly one level marker: {item.nodeid}: {sorted(levels)}")
        descriptions.append({
            "node_id": item.nodeid, "description": " ".join(doc.split()),
            "parameter_id": item.callspec.id if hasattr(item, "callspec") else None,
            "level": next(iter(levels)), "concerns": sorted(markers & CONCERNS),
            "resources": sorted(markers & RESOURCES),
        })
    return sorted(descriptions, key=lambda case: case["node_id"])
