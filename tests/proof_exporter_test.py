"""The installed exporter deterministically exports current proofs and candidate namespaces.

T03 and T02 receipts retain the historical fixed-model/input byte checkpoint.
Current proofs bind their actual installed inputs and library instead of that golden.
"""

from collections.abc import Callable
import hashlib
import json
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult
from migration_check.import_path import merged_search_path
from migration_check.source_closure import lean_process

pytestmark = [pytest.mark.e2e, pytest.mark.kernel, pytest.mark.requires_lean, pytest.mark.requires_native]
CASES = {"small": ("approved", "add_column_then_table", "approved/schema.sql", "3.51.0"),
         "refutation": ("approved", "missing_required_column", "approved/schema.sql", "3.51.0"),
         "atuin": ("atuin/approved", "atuin", "atuin/schema.sql", "3.46.0")}
"""Current shipped positive, refutation and Atuin inputs."""
EXPECTED = {"small": ("VERIFIED", ["Init", "SqliteVerifier.Demonstration", "SqliteVerifier.Library"]),
            "refutation": ("VIOLATED", ["Init", "SqliteVerifier.Library"]),
            "atuin": ("VERIFIED", ["Init", "SqliteVerifier", "Std"])}
"""Independent status and exact trusted-import expectations for the shipped examples."""


def file_digest(path: Path) -> str:
    """Bind the actual bytes consumed by the current native acceptance check."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def input_digests(examples: Path, approved: str, candidate: str, schema: str) -> dict[str, str]:
    """Bind SQL and all local Lean sources available to the selected contract and candidate."""
    files = {examples / schema, examples / candidate / "migration.sql"}
    for directory in (examples / approved, examples / candidate):
        files.update(directory.rglob("*.lean"))
    return {path.relative_to(examples).as_posix(): file_digest(path) for path in sorted(files)}


@pytest.fixture(scope="session")
def exporter_runtime_identity(runtime_root: Path, lean_sysroot: Path) -> dict[str, object]:
    """Retain actual runtime code, executable and compiled-library identities in native evidence."""
    library = runtime_root / ".lake/build/lib/lean"
    executables = {name: runtime_root / name for name in ("bin/migration-check", "build/sqlite-parser",
        "build/sqlite-parser-3.46.0", ".lake/build/bin/migration-proof-exporter",
        ".lake/build/bin/migration-proof-checker", ".lake/build/bin/migration-bundle-checker")}
    executables["lean/bin/lean"] = lean_sysroot / "bin/lean"
    return {"runtime": str(runtime_root.resolve()), "sysroot": str(lean_sysroot.resolve()),
        "library": str(library.resolve()),
        "librarySha256": {path.relative_to(library).as_posix(): file_digest(path)
                          for path in sorted(library.rglob("*")) if path.is_file()},
        "runtimePythonSha256": {path.relative_to(runtime_root).as_posix(): file_digest(path)
                                for path in sorted((runtime_root / "migration_check").rglob("*.py"))},
        "executables": {name: {"path": str(path.resolve()), "sha256": file_digest(path)}
                        for name, path in executables.items()}}


def prepare_check(runtime: Path, examples: Path, temporary: Path, approved: str, candidate: str,
                  schema: str, profile: str, run: Callable[..., CommandResult]) -> tuple[Path, dict[str, object]]:
    """Exercise public preparation and acceptance with one independently retained bundle."""
    common = ["--profile", profile, "--format", "json", "--schema", str(examples / schema),
              "--requirements", str(examples / approved / "Requirements.lean"),
              "--interpretation", str(examples / approved / "Interpretation.lean"),
              "--migration", str(examples / candidate / "migration.sql")]
    bundle = temporary / "proof.bundle"
    launcher = str(runtime / "bin/migration-check")
    prepared = run([launcher, "prepare", *common,
        "--next-interpretation", str(examples / candidate / "NextInterpretation.lean"),
        "--proofs", str(examples / candidate / "Proofs.lean"),
        "--workspace", str(temporary / "agent"), "--output", str(bundle)], cwd=temporary, timeout=180)
    assert prepared.returncode == 0 and prepared.json_object()["status"] == "PREPARED", prepared.diagnostic()
    checked = run([launcher, "verify-bundle", *common, "--bundle", str(bundle),
        "--approved-baseline", str(examples / approved / "baseline.json")], cwd=temporary, timeout=120)
    report = checked.json_object()
    assert checked.returncode == (0 if report["status"] == "VERIFIED" else 1), checked.diagnostic()
    report["cliReturncode"] = checked.returncode
    return bundle, report


@pytest.mark.parametrize("name", CASES)
def test_current_native_export(name: str, runtime_root: Path, example_factory: Callable[[str], Path],
        tmp_path: Path, command_runner: Callable[..., CommandResult],
        exporter_runtime_identity: dict[str, object],
        record_testsuite_property: Callable[[str, object], None]) -> None:
    """Fresh preparations are byte-identical and independently checked against exact current inputs."""
    approved, candidate, schema, profile = CASES[name]
    status, imports = EXPECTED[name]
    examples = example_factory(".")
    hashes = input_digests(examples, approved, candidate, schema)
    assert hashes == input_digests(runtime_root / "examples", approved, candidate, schema)
    payloads: list[bytes] = []
    reports: list[dict[str, object]] = []
    header = {"bundle": 1, "trusted_imports": imports}
    for label in ("first", "second"):
        workspace = tmp_path / label
        workspace.mkdir()
        bundle, report = prepare_check(runtime_root, examples, workspace, *CASES[name], command_runner)
        payload = bundle.read_bytes()
        assert json.loads(payload.splitlines()[0]) == header
        assert report["status"] == status, report
        if status == "VERIFIED":
            expected = {"schema.sql": hashes[schema], "migration.sql": hashes[f"{candidate}/migration.sql"],
                "profile": profile, "bundle": file_digest(bundle),
                **{f"approved/{path.removeprefix(approved + '/')}": digest for path, digest in hashes.items()
                   if path.startswith(approved + "/") and path.endswith(".lean")}}
            assert isinstance(report["inputs"], dict) and expected.items() <= report["inputs"].items(), report
        payloads.append(payload)
        reports.append(report)
    assert payloads[0] == payloads[1]
    assert hashes == input_digests(examples, approved, candidate, schema)
    record_testsuite_property(f"current-export-{name}", json.dumps({"inputSha256": hashes,
        "runtime": exporter_runtime_identity, "header": header, "bundleBytes": len(payloads[0]),
        "bundleSha256": hashlib.sha256(payloads[0]).hexdigest(), "checks": reports}, sort_keys=True))


def test_candidate_module_under_library_namespace(runtime_root: Path,
        example_factory: Callable[[str], Path], tmp_path: Path,
        command_runner: Callable[..., CommandResult]) -> None:
    """A used caller-owned declaration under SqliteVerifier must survive omission and kernel replay."""
    examples = example_factory(".")
    candidate = examples / "add_column_then_table"
    helper = candidate / "SqliteVerifier/Candidate.lean"
    helper.parent.mkdir()
    helper.write_text("""import Generated
import SqliteVerifier.Demonstration
namespace SqliteVerifier.Candidate
/-- The caller-owned helper establishes this example's complete migration target. -/
theorem checked : Generated.expected := SqliteVerifier.Demonstration.migrationCorrect
end SqliteVerifier.Candidate
""")
    (candidate / "Proofs.lean").write_text("""import SqliteVerifier.Candidate
/-- This proof requires the caller-owned library-like module to be exported. -/
theorem Proofs.migrationCorrect : Generated.expected := SqliteVerifier.Candidate.checked
""")
    _bundle, report = prepare_check(runtime_root, examples, tmp_path, *CASES["small"], command_runner)
    assert report["status"] == "VERIFIED", report


@pytest.mark.parametrize("arguments,diagnostic", [
    (["--omit=Missing", "SqliteVerifier", "--", "SqliteVerifier.Schema"], "omitted module is not imported"),
    (["--omit=", "SqliteVerifier", "--", "SqliteVerifier.Schema"], "Lean name"),
    (["--skip-trusted", "SqliteVerifier"], "unknown exporter option"),
    ([], "no export module"),
])
def test_invalid_exporter_arguments(runtime_root: Path, tmp_path: Path,
        command_runner: Callable[..., CommandResult], arguments: list[str], diagnostic: str) -> None:
    """An absent omission module or invalid request fails before producing a successful export."""
    result = command_runner([str(runtime_root / ".lake/build/bin/migration-proof-exporter"), *arguments],
        cwd=tmp_path, timeout=30, environment={"LEAN_SYSROOT": str(runtime_root / "lean"),
            "LEAN_PATH": str(runtime_root / ".lake/build/lib/lean")})
    assert result.returncode != 0 and diagnostic in result.stderr, result.diagnostic()


def test_omissions_follow_transitive_module_origins(runtime_root: Path, lean_sysroot: Path,
        tmp_path: Path, command_runner: Callable[..., CommandResult]) -> None:
    """Trusted imports omit transitive declarations even in unrelated namespaces, while siblings export."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    library.mkdir()
    candidate.mkdir()
    modules = [(library, "Trusted/Base", "def OtherNamespace.base : Nat := 7\n"),
        (library, "Trusted/Root", "import Trusted.Base\ndef OtherNamespace.root : Nat := OtherNamespace.base\n"),
        (candidate, "Trusted/Candidate", "import Trusted.Root\ndef Trusted.local : Nat := OtherNamespace.root\n"),
        (candidate, "Proofs", "import Trusted.Candidate\ndef exported : Nat := Trusted.local\n")]
    for directory, module, contents in modules:
        source = directory / (module + ".lean")
        source.parent.mkdir(exist_ok=True)
        source.write_text(contents)
        lean_process(lean_sysroot, library, [candidate], source, directory,
            ["-R", str(directory), "-o", str(source.with_suffix(".olean"))], "fixture", timeout=10)
    with merged_search_path([library, candidate], tmp_path) as paths:
        result = command_runner([str(runtime_root / ".lake/build/bin/migration-proof-exporter"),
            "--omit=Trusted.Root", "Proofs", "--", "exported"], cwd=tmp_path, timeout=30,
            environment={"LEAN_SYSROOT": str(lean_sysroot), "LEAN_PATH": ":".join(map(str, paths))})
    assert result.returncode == 0, result.diagnostic()
    names: dict[int, str] = {0: ""}
    declarations: list[str] = []
    for line in result.stdout.splitlines():
        value = json.loads(line)
        if "in" in value:
            component = value["str"]
            names[value["in"]] = ".".join(filter(None, (names[component["pre"]], component["str"])))
        if "def" in value:
            declarations.append(names[value["def"]["name"]])
    assert declarations == ["Trusted.local", "exported"]
