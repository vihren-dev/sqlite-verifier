"""Require explicit role files and their Lean source roots to belong to the retained input identity."""

from collections.abc import Sequence
from pathlib import Path

ROLE_PATH_FLAGS = {"--schema", "--migration", "--requirements", "--interpretation",
                   "--next-interpretation", "--proofs", "--approved-baseline"}
"""Current public role/baseline flags whose paths affect a verification request."""
LEAN_SOURCE_FLAGS = {"--requirements", "--interpretation", "--next-interpretation", "--proofs"}
"""Lean roles resolve sibling source dependencies, so a file-only identity cannot cover their closure."""


def require_recorded_role_roots(arguments: Sequence[str], roots: Sequence[Path]) -> None:
    """Allow flexible actual argv while refusing role inputs or sibling Lean sources outside recorded roots."""
    for index, argument in enumerate(arguments):
        flag, separator, inline = argument.partition("=")
        if flag not in ROLE_PATH_FLAGS:
            continue
        value = inline if separator else arguments[index + 1] if index + 1 < len(arguments) else ""
        if not value or value.startswith("--"):
            raise ValueError(f"Role input {flag} has no explicit path; supply its actual file")
        if not Path(value).is_absolute():
            raise ValueError(f"Role input {flag} is relative; use an absolute path for fresh command directories")
        path = Path(value).resolve(strict=True)
        if not path.is_file():
            raise ValueError(f"Role input {flag} at {path} is not a regular file; supply its actual file")
        if not any((root.is_dir() and path.is_relative_to(root.resolve(strict=True))) or
                   (flag not in LEAN_SOURCE_FLAGS and path == root.resolve(strict=True)) for root in roots):
            raise ValueError(f"Role input {flag} at {path} is outside recorded roots; include its source directory")
