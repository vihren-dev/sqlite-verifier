"""Exercise the actual kernel executable with harmless adversarial Lean modules."""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/kernel_gate"
LIBRARY = Path(os.environ.get("KERNEL_GATE_LIBRARY", ROOT / ".lake/build/lib/lean"))
CHECKER = ROOT / ".lake/build/bin/migration-proof-checker"


def run(arguments: list[str], directory: Path, environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
    """Bound compiler and checker processes and capture diagnostics for failed assertions."""
    return subprocess.run(arguments, cwd=directory, env=environment,
                          capture_output=True, text=True, timeout=30)


def compile_module(directory: Path, module: str, source: str, environment: dict[str, str]) -> None:
    """Compile only checked-in harmless fixtures, including intentionally invalid proofs."""
    (directory / f"{module}.lean").write_text(source)
    compiler = str(Path(environment["LEAN_SYSROOT"]) / "bin/lean")
    result = run([compiler, "-o", f"{module}.olean", f"{module}.lean"], directory, environment)
    assert result.returncode == 0, result.stdout + result.stderr


def main() -> None:
    """Accept the honest proof and reject independent trust-boundary attacks."""
    with tempfile.TemporaryDirectory(prefix="kernel-gate-") as temporary:
        root = Path(temporary)
        trusted, candidate = root / "trusted", root / "candidate"
        trusted.mkdir()
        candidate.mkdir()
        environment = dict(os.environ)
        if "LEAN_SYSROOT" not in environment:
            prefix = run(["lean", "--print-prefix"], ROOT, environment)
            assert prefix.returncode == 0, prefix.stderr
            environment["LEAN_SYSROOT"] = prefix.stdout.strip()
        missing_root = dict(environment)
        missing_root.pop("LEAN_SYSROOT")
        bad_environment = run([str(CHECKER), str(LIBRARY), str(trusted), str(candidate)], root, missing_root)
        assert bad_environment.returncode != 0 and "LEAN_SYSROOT" in bad_environment.stderr
        bad_path = run([str(CHECKER), ".", str(trusted), str(candidate)], root, environment)
        assert bad_path.returncode != 0 and "absolute existing directory" in bad_path.stderr
        environment["LEAN_PATH"] = os.pathsep.join(map(str, (LIBRARY, trusted)))
        for module in ("Requirements", "Interpretation", "SqlInputs"):
            compile_module(trusted, module, (FIXTURES / f"{module}.lean").read_text(), environment)
        environment["LEAN_PATH"] += os.pathsep + str(candidate)
        for module in ("NextInterpretation", "Generated"):
            compile_module(candidate, module, (FIXTURES / f"{module}.lean").read_text(), environment)
        valid = (FIXTURES / "Proofs.lean").read_text()
        cases = {
            "valid": (valid, ""),
            "initializer ignored": (valid + '\ninitialize IO.eprintln "CANDIDATE_INITIALIZER_RAN"\n', ""),
            "forged kernel body": ("import Lean\nimport Generated\nset_option debug.skipKernelTC true in\nrun_elab Lean.addDecl (.thmDecl { name := `Proofs.migrationCorrect, levelParams := [], type := Lean.mkConst `Generated.expected, value := Lean.mkConst `True.intro })", "while replaying"),
            "wrong theorem": ("import Generated\ntheorem Proofs.migrationCorrect : True := trivial", "reconstructed"),
            "sorry": ("import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := by sorry", "sorryAx"),
            "transitive axiom": ("import Generated\naxiom forbidden : Generated.expected\ndef helper := forbidden\ntheorem Proofs.migrationCorrect : Generated.expected := helper", "forbidden"),
            "changed protected contract": ("import Lean\ndef Requirements.contract : Nat := 0\ntheorem Proofs.migrationCorrect : True := trivial", "modified protected"),
            "changed protected SQL": ("import Lean\ndef Generated.script : Nat := 0\ntheorem Proofs.migrationCorrect : True := trivial", "modified protected"),
            "unsafe proof": ("import Generated\nunsafe def Proofs.migrationCorrect : True := True.intro", "Proofs.migrationCorrect"),
        }
        for label, (source, diagnostic) in cases.items():
            compile_module(candidate, "Proofs", source, environment)
            result = run([str(CHECKER), str(LIBRARY), str(trusted), str(candidate)], root, environment)
            assert (result.returncode == 0) == (label in ("valid", "initializer ignored")), (label, result.stdout, result.stderr)
            assert diagnostic in result.stderr, (label, result.stderr)
            assert "CANDIDATE_INITIALIZER_RAN" not in result.stdout + result.stderr
        # A forged convenience alias must not replace the reconstructed target.
        compile_module(candidate, "Generated", "import SqlInputs\nimport NextInterpretation\ndef Generated.expected : Prop := True", environment)
        compile_module(candidate, "Proofs", "import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := trivial", environment)
        result = run([str(CHECKER), str(LIBRARY), str(trusted), str(candidate)], root, environment)
        assert result.returncode != 0 and "reconstructed" in result.stderr, result.stderr
    print("Kernel gate: honest proof accepted, initializer ignored; eight trust-boundary attacks rejected.")


if __name__ == "__main__":
    main()
