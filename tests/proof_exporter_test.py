"""The installed exporter preserves baseline bytes and exports candidate library namespaces."""

from collections.abc import Callable
import hashlib
import json
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult
from migration_check.import_path import merged_search_path
from migration_check.source_closure import lean_process

pytestmark = [pytest.mark.e2e, pytest.mark.kernel, pytest.mark.requires_lean, pytest.mark.requires_native]
ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "reports/20261006-lean-4341-upgrade-darwin.json"
"""Immutable T03 receipt with the old producer's exact input and bundle bindings."""
CASES = {"small": ("approved", "add_column_then_table", "approved/schema.sql", "3.51.0"),
         "refutation": ("approved", "missing_required_column", "approved/schema.sql", "3.51.0"),
         "atuin": ("atuin/approved", "atuin", "atuin/schema.sql", "3.46.0")}
"""Shipped examples used by both T03 native exporter baselines."""


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
    checked = run([launcher, "verify-bundle", *common, "--bundle", str(bundle)], cwd=temporary, timeout=120)
    report = checked.json_object()
    assert checked.returncode == (0 if report["status"] == "VERIFIED" else 1), checked.diagnostic()
    return bundle, report


@pytest.mark.parametrize("name", CASES)
def test_native_baseline_bytes(name: str, runtime_root: Path, example_factory: Callable[[str], Path],
                              tmp_path: Path, command_runner: Callable[..., CommandResult]) -> None:
    """The new producer preserves actual upgraded-toolchain input bindings, bytes and status."""
    baseline = next(case for case in json.loads(BASELINE.read_text())["exporterBaseline"]["cases"]
                    if case["name"] == name)
    examples = example_factory(".")
    for relative, expected in baseline["inputSha256"].items():
        assert hashlib.sha256((examples / relative.removeprefix("examples/")).read_bytes()).hexdigest() == expected
    bundle, report = prepare_check(runtime_root, examples, tmp_path, *CASES[name], command_runner)
    payload = bundle.read_bytes()
    assert len(payload) == baseline["bundleBytes"]
    assert hashlib.sha256(payload).hexdigest() == baseline["bundleSha256"]
    assert report["status"] == baseline["status"], report


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
