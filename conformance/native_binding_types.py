"""Type the native replay inputs separately from JSON evidence that contains no Python bytes."""

from typing import TypedDict

from conformance.case_format import Json
from conformance.native_connection import Row


class NativeBindingReplayArguments(TypedDict, total=False):
    """Describe checked keyword arguments for the shared recorder, including decoded typed cells."""

    setup_parameters: list[list[Row]]
    setup_parameter_names: list[list[list[str | None]]]
    parameter_names: list[list[str | None]]
    setup_helpers: list[str]
    migration_readonly: bool
    migration_readonly_spans: list[tuple[int, int]]
    auxiliary_replay: bool
    tcl_calls: dict[str, Json]
    source_setup_commands: list[str | dict[str, Json]]
    setup_call_indices: list[int]
