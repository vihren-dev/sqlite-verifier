"""Check the pinned tools without claiming migration verification."""

from pathlib import Path
import subprocess


def run(*arguments: str) -> str:
    """Bound every external check and retain stderr when a tool fails."""
    return subprocess.run(
        arguments, check=True, text=True, capture_output=True, timeout=10
    ).stdout.strip()


def main() -> None:
    """Check Lean's release and SQLite's native schema operations."""
    expected_lean = Path("lean-toolchain").read_text().strip().split(":v")[1]
    assert f"version {expected_lean}," in run("lean", "--version")
    assert expected_lean in run("lake", "--version")
    assert run("sqlite3", ":memory:", "SELECT sqlite_version();") == "3.51.0"
    assert run("sqlite3", ":memory:", "SELECT sqlite_source_id();") == (
        "2025-11-04 19:38:17 "
        "fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b"
    )
    result = run(
        "sqlite3", "-batch", ":memory:",
        "CREATE TABLE records (id INTEGER, value TEXT);"
        "INSERT INTO records VALUES (7, 'retained');"
        "ALTER TABLE records ADD COLUMN extra TEXT;"
        "SELECT id, value, extra IS NULL FROM records;",
    )
    assert result == "7|retained|1", result
    assert run("sqlite3-3.46.0", ":memory:", "SELECT sqlite_version();") == "3.46.0"
    assert run("sqlite3-3.46.0", ":memory:", "SELECT sqlite_source_id();") == (
        "2024-05-23 13:25:27 "
        "96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e"
    )
    print("Pinned Lean/Lake and SQLite schema-extension smoke checks passed.")


if __name__ == "__main__":
    main()
