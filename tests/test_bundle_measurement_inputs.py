"""Protected/candidate role paths and reachable sibling source roots must be retained identities."""

from pathlib import Path

import pytest

from tools.bundle_measurement_inputs import require_recorded_role_roots


def test_split_inline_roles_and_source_siblings_bound(tmp_path: Path) -> None:
    """Both public path syntaxes bind Lean roles to complete directories and SQL to actual files."""
    source = tmp_path / "source"
    source.mkdir()
    (source / "Proofs.lean").write_bytes(b"import Helper")
    (source / "Helper.lean").write_bytes(b"namespace Helper")
    schema = tmp_path / "schema.sql"
    schema.write_bytes(b"CREATE TABLE t(x);")
    require_recorded_role_roots(("--schema", str(schema), "--proofs=" + str(source / "Proofs.lean")), (schema, source))
    with pytest.raises(ValueError, match="outside recorded roots"):
        require_recorded_role_roots(("--proofs", str(source / "Proofs.lean")), (source / "Proofs.lean",))
    with pytest.raises(ValueError, match="outside recorded roots"):
        require_recorded_role_roots(("--schema", str(schema)), (source,))


def test_linked_role_requires_actual_resolved_source_root(tmp_path: Path) -> None:
    """A linked role cannot hide its reachable sibling dependencies outside the input manifest."""
    source, external = tmp_path / "source", tmp_path / "external"
    source.mkdir()
    external.mkdir()
    (external / "Proofs.lean").write_bytes(b"import Helper")
    (source / "Proofs.lean").symlink_to(external / "Proofs.lean")
    with pytest.raises(ValueError, match="outside recorded roots"):
        require_recorded_role_roots(("--proofs", str(source / "Proofs.lean")), (source,))
    require_recorded_role_roots(("--proofs", str(source / "Proofs.lean")), (source, external))


@pytest.mark.parametrize("arguments", [("--schema",), ("--proofs=",), ("--schema", "--proofs")])
def test_missing_role_path_diagnoses_flag(arguments: tuple[str, ...], tmp_path: Path) -> None:
    """Missing paths are refused before any process or evidence directory can be created."""
    with pytest.raises(ValueError, match="has no explicit path"):
        require_recorded_role_roots(arguments, (tmp_path,))


def test_relative_or_directory_role_is_refused(tmp_path: Path) -> None:
    """Fresh command directories cannot silently redirect relative roles or treat folders as source files."""
    with pytest.raises(ValueError, match="is relative"):
        require_recorded_role_roots(("--schema", "schema.sql"), (tmp_path,))
    with pytest.raises(ValueError, match="not a regular file"):
        require_recorded_role_roots(("--requirements", str(tmp_path)), (tmp_path,))
