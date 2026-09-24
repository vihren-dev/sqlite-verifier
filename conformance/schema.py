"""Typed records for the bounded upstream import and independent observations."""

from typing import TypedDict


class Coverage(TypedDict):
    """Counts refer to textual source calls, not dynamically expanded Tcl executions."""
    selected_call_instances: int
    selected_distinct_ids: int
    upstream_textual_call_sites: int
    upstream_distinct_textual_ids: int


class ConnectionSetup(TypedDict):
    """The original C-API configuration and its equivalent native-shell directive."""
    upstream: str
    shell: str


class Prerequisite(TypedDict):
    """Exact SQL establishing a persistent dependency from an earlier assertion."""
    upstream_id: str
    sql: str


class Case(TypedDict):
    """One invocation preserves its duplicate-safe identity and upstream expectation."""
    upstream_id: str
    occurrence: int
    source_start_line: int
    source_end_line: int
    sql: str
    expected_tcl: str
    expected_flat: list[str]


class Fixture(TypedDict):
    """A selected slice explicitly reports its unproved formal-model status."""
    source: str
    profile: str
    coverage: Coverage
    connection_setup: list[ConnectionSetup]
    prerequisite_setup: list[Prerequisite]
    cases: list[Case]
    model_status: str
