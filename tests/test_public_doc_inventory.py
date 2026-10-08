"""Real compiler fixtures distinguish authored API items from generated names and fail documentation gaps."""

import os
import json
from pathlib import Path
import subprocess

import pytest

from tools.public_doc_inventory import inventory, require_complete
from tools.public_doc_coverage import mapping, module_coverage, position, sequence, text

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/public_doc_inventory/InventoryFixture.lean"
"""One compiling source covers fields, constructors, defaults, deriving and generated-looking names."""
pytestmark = [pytest.mark.integration, pytest.mark.environment, pytest.mark.requires_lean]


def compiler(runtime_root: Path) -> Path:
    """Use the selected pinned runtime compiler; inventory code never depends on Elan."""
    return runtime_root / "lean/bin/lean"


def fixture_report(tmp_path: Path, runtime_root: Path, source: str,
                   dependencies: dict[str, str] | None = None) -> dict[str, object]:
    """Compile original source and its reference file, then run the real metadata inventory."""
    path = tmp_path / "InventoryFixture.lean"
    path.write_text(source)
    lean = compiler(runtime_root)
    original = os.environ.get("LEAN_PATH")
    os.environ["LEAN_PATH"] = str(tmp_path)
    try:
        for module, contents in (dependencies or {}).items():
            (tmp_path / f"{module}.lean").write_text(contents)
        for module in [*(dependencies or {}), "InventoryFixture"]:
            subprocess.run([str(lean), "-o", f"{module}.olean", "-i", f"{module}.ilean", f"{module}.lean"],
                           cwd=tmp_path, check=True, capture_output=True, text=True, timeout=15)
        return inventory(tmp_path, "InventoryFixture", lean, tmp_path / "coverage.json")
    finally:
        if original is None:
            os.environ.pop("LEAN_PATH", None)
        else:
            os.environ["LEAN_PATH"] = original


def modules(report: dict[str, object]) -> list[dict[str, object]]:
    """Read validated report objects without assuming a fixed public import closure."""
    return [mapping(module, "coverage module") for module in sequence(report["modules"], "modules")]


def rows(report: dict[str, object], category: str) -> list[dict[str, object]]:
    """Keep exact compiler names and evidence for the selected coverage category."""
    return [mapping(row, category) for module in modules(report) for row in sequence(module[category], category)]


def test_invalid_selection_identifies_its_declaration() -> None:
    """A malformed compiler selection reports the precise module/declaration to rebuild."""
    with pytest.raises(ValueError, match="InventoryFixture: Data.first"):
        position([True, 0, 1, 0], "InventoryFixture: Data.first")


@pytest.mark.parametrize("damage", ["module", "declaration"])
def test_invalid_documentation_array_identifies_its_source(tmp_path: Path, damage: str) -> None:
    """Malformed documentation metadata reports its module and, when present, its declaration."""
    source, references = tmp_path / "fixture.lean", tmp_path / "fixture.ilean"
    source.write_text("def item := 1\n")
    identity = json.dumps({"c": {"m": "InventoryFixture", "n": "item"}})
    references.write_text(json.dumps({"module": "InventoryFixture", "references": {
        identity: {"definition": [0, 4, 0, 8]}}}))
    slot: dict[str, object] = {"selection": [0, 4, 0, 8], "documentation": "broken"}
    raw: dict[str, object] = {"module": "InventoryFixture", "source": str(source),
        "references": str(references), "declarators": [slot],
        "constants": [{"name": "item", "verso": True}], "checked_module_documentation_ranges": []}
    if damage == "module":
        raw["checked_module_documentation_ranges"] = "broken"
    context = "InventoryFixture: checked module documentation" if damage == "module" else "InventoryFixture: item documentation"
    with pytest.raises(ValueError, match=context):
        module_coverage(raw)


def test_complete_authored_coverage_excludes_generated_constants(tmp_path: Path, runtime_root: Path,
        monkeypatch: pytest.MonkeyPatch) -> None:
    """The selected compiler gives complete coverage even when ambient lean fails; generated helpers are explained."""
    ambient = tmp_path / "ambient compiler"
    ambient.mkdir()
    (ambient / "lean").write_text("#!/bin/sh\nexit 255\n")
    (ambient / "lean").chmod(0o755)
    monkeypatch.setenv("PATH", str(ambient) + os.pathsep + os.environ.get("PATH", ""))
    monkeypatch.delenv("LEAN_SYSROOT", raising=False)
    report = fixture_report(tmp_path, runtime_root, FIXTURE.read_text())
    assert report["complete"] is True
    authored = {text(row["name"], "authored name"): row for row in rows(report, "authored")}
    assert set(authored) == {"Choice", "Choice.value", "Data", "Data.create", "Data.first", "Data.second",
                             "Data.third", "ImplicitConstructor", "ImplicitConstructor.amount",
                             "instReprPretend", "LooksGenerated._example", "«µ_value»", "instInhabitedData",
                             "documentedWithCommands"}
    assert authored["Data.first"]["role"] == authored["Data.second"]["role"] == "field"
    assert authored["Data.first"]["selection"] != authored["Data.second"]["selection"]
    assert authored["Choice.value"]["role"] == authored["Data.create"]["role"] == "constructor"
    excluded = {text(row["name"], "excluded name"): row for row in rows(report, "excluded") if "name" in row}
    assert {"Choice.rec", "ImplicitConstructor.mk", "instReprChoice", "instDecidableEqChoice"} <= set(excluded)
    assert all(excluded[name]["reason"] for name in ("Choice.rec", "ImplicitConstructor.mk", "instReprChoice"))
    assert excluded["temporaryDocValue"]["checked_documentation_range"]
    assert all(not module["unclassified"] for module in modules(report))


def test_module_documentation_commands_have_compiled_exclusion_evidence(tmp_path: Path, runtime_root: Path) -> None:
    """Compiled Verso module-comment ranges identify temporary definitions and examples without guessing names."""
    source = ('set_option doc.verso true\n/-!\n```lean\n'
              'def temporaryModuleDocValue : Nat := 5\n'
              'example : temporaryModuleDocValue = 5 := rfl\n```\n-/\n'
              '/-- The only exported declaration follows the checked walkthrough. -/\n'
              'def exportedAfterDocs : Nat := 1\n')
    report = fixture_report(tmp_path, runtime_root, source)
    assert report["complete"] is True
    assert {row["name"] for row in rows(report, "authored")} == {"exportedAfterDocs"}
    evidence = {row["name"]: row for row in rows(report, "excluded") if "name" in row}
    assert evidence["temporaryModuleDocValue"]["checked_documentation_range"]
    assert evidence["_example"]["checked_documentation_range"]


def test_imported_public_module_is_discovered_from_compiler_closure(tmp_path: Path, runtime_root: Path) -> None:
    """A newly imported module participates in coverage without changing an inventory name list."""
    dependency = "set_option doc.verso true\n/-- An authored item in a new imported module. -/\ndef importedItem := 1\n"
    report = fixture_report(tmp_path, runtime_root, "import ImportedProofs\n" + FIXTURE.read_text(),
                            {"ImportedProofs": dependency})
    assert report["complete"] is True
    assert {module["module"] for module in modules(report)} == {"InventoryFixture", "ImportedProofs"}
    assert "importedItem" in {row["name"] for row in rows(report, "authored")}


def test_unrecognized_authored_command_fails_closed(tmp_path: Path, runtime_root: Path) -> None:
    """An original compiler binder from custom syntax must be classified before coverage can pass."""
    source = ('import Lean\nsyntax "authored " ident : command\n'
              'macro_rules | `(authored $identifier:ident) => `(def $identifier := 0)\n'
              'authored customDeclaration\n')
    report = fixture_report(tmp_path, runtime_root, source)
    assert report["complete"] is False
    assert "customDeclaration" in {row.get("name") for row in rows(report, "unclassified")}
    assert not require_complete(report, tmp_path / "coverage.json")


@pytest.mark.parametrize("damage", ["field", "constructor", "definition", "ordinary", "inherited"])
def test_missing_or_unchecked_docs_fail_the_real_gate(tmp_path: Path, runtime_root: Path, damage: str) -> None:
    """A source item cannot disappear from coverage when its own checked documentation is removed."""
    source = FIXTURE.read_text()
    if damage == "field":
        source = source.replace("/-- Two independently authored natural-number fields. -/", "")
        expected = {"Data.first", "Data.second"}
    elif damage == "constructor":
        source = source.replace("/-- Store the supplied natural number. -/", "")
        expected = {"Choice.value"}
    elif damage == "definition":
        source = source.replace("/-- This authored definition deliberately looks like a deriving helper. -/", "")
        expected = {"instReprPretend"}
    elif damage == "ordinary":
        source = source.replace("set_option doc.verso true", "set_option doc.verso false").replace("{lean}`0`", "`0`")
        expected = {"Data.first", "Choice.value", "instReprPretend"}
    else:
        source += "\n@[inherit_doc instReprPretend]\ndef borrowed : Nat := 4\n"
        expected = {"borrowed"}
    report = fixture_report(tmp_path, runtime_root, source)
    assert report["complete"] is False
    gaps = {text(row["name"], "authored name") for row in rows(report, "authored") if not row["verso"]}
    assert expected <= gaps
    assert not require_complete(report, tmp_path / "coverage.json")
