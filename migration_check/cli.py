"""One-script offline verification; source elaboration alone never means VERIFIED."""

import argparse
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from collections.abc import Sequence

from .diagnostics import Rejection
from .inputs import generated_inputs, read_sql
from .runtime import Runtime
from .process import run_process
from .stage_store import StageStore

__all__ = ["arguments", "main", "read_sql", "verify"]


class Arguments(argparse.ArgumentParser):
    """Render usage failures using the same diagnostic protocol as later failures."""

    def error(self, message: str) -> None:
        """Keep missing flags, including profile, distinguishable from unproved obligations."""
        raise Rejection("INPUT_ERROR", message)


def common_arguments(command: argparse.ArgumentParser, candidate: tuple[str, ...]) -> None:
    """Contract inputs shared by all commands, plus the named candidate inputs."""
    command.add_argument("--profile", required=True, help="Exact SQLite semantic version: 3.51.0 or 3.46.0")
    for name in ("schema", "interpretation", "migration", "requirements", *candidate):
        command.add_argument("--" + name, required=True, type=Path)
    command.add_argument("--format", choices=("human", "json"), default="human")


def arguments(values: Sequence[str]) -> argparse.Namespace:
    """Expose `verify` and the experimental ADR 0003 `prepare`/`verify-bundle` commands."""
    parser = Arguments(prog="migration-check", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True, parser_class=Arguments)
    verify = commands.add_parser("verify", help="Check one migration under approved Lean requirements")
    common_arguments(verify, ("next-interpretation", "proofs"))
    verify.add_argument("--artifacts", type=Path, help="Create a directory with generated SQL and input hashes")
    verify.add_argument("--approved-baseline", type=Path, help="Require unchanged approved source/dependency hashes")
    prepare = commands.add_parser("prepare", help="Experimental: build and export a proof bundle (agent side)")
    common_arguments(prepare, ("next-interpretation", "proofs"))
    prepare.add_argument("--workspace", required=True, type=Path, help="Persistent agent build directory")
    prepare.add_argument("--output", required=True, type=Path, help="Bundle file to write")
    bundle = commands.add_parser("verify-bundle", help="Experimental: check a proof bundle without candidate source")
    common_arguments(bundle, ("bundle",))
    bundle.add_argument("--approved-baseline", type=Path, help="Require unchanged approved source/dependency hashes")
    return parser.parse_args(values)


def verify(options: argparse.Namespace) -> dict[str, object]:
    """Seal SQL and approved sources, compile in isolation, and invoke the independent gate."""
    inputs = generated_inputs(options)
    runtime = Runtime.locate(inputs.profile.engine)
    from .compile import CompileError, EXPECTED_SOURCE, compile_project

    schema_hash, starting, generated = inputs.schema_hash, inputs.schema_source, inputs.sql_source
    if options.artifacts is not None:
        options.artifacts.mkdir(parents=True, exist_ok=False)
        (options.artifacts / "SqlInputs.lean").write_text(generated, encoding="utf-8")
        (options.artifacts / "SchemaInputs.lean").write_text(starting, encoding="utf-8")
        (options.artifacts / "Generated.lean").write_text(EXPECTED_SOURCE, encoding="utf-8")
    with TemporaryDirectory(prefix="migration-check-") as temporary:
        workspace = Path(temporary).resolve()
        try:
            compiled = compile_project(
                sysroot=runtime.sysroot, library=runtime.library, requirements=options.requirements,
                interpretation=options.interpretation, next_interpretation=options.next_interpretation,
                proofs=options.proofs, schema_inputs=starting, sql_inputs=generated, workspace=workspace,
                approved_baseline=options.approved_baseline, schema_hash=schema_hash,
                store=StageStore.configured())
        except CompileError as error:
            raise Rejection("UNVERIFIED", str(error)) from error
        hashes = {**compiled.hashes, **inputs.hashes}
        if options.artifacts is not None:
            (options.artifacts / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n", encoding="utf-8")
        output = workspace / "gate-output"
        output.mkdir()
        checked = run_process(
            [str(runtime.checker), str(runtime.library), str(compiled.trusted), str(compiled.candidate)],
            write_root=output, environment={"LEAN_SYSROOT": str(runtime.sysroot)}, timeout=30)
        if checked.returncode == 2:
            raise Rejection("VIOLATED", "A kernel-checked argument refutes the supplied verification contract")
        if checked.returncode != 0:
            raise Rejection("UNVERIFIED", checked.stderr.strip() or "Independent kernel gate rejected the proof")
    return {"status": "VERIFIED", "profile": hashes["profile"], "statements": inputs.statements, "inputs": hashes}


def main(values: Sequence[str]) -> int:
    """Return zero exactly for an independently accepted proof, with optional JSON diagnostics."""
    json_output = any(tuple(values[index:index + 2]) == ("--format", "json") for index in range(len(values)))
    json_output = json_output or "--format=json" in values
    try:
        options = arguments(values)
        if options.command == "prepare":
            from .prepare import prepare
            result = prepare(options)
        elif options.command == "verify-bundle":
            from .bundle import verify_bundle
            result = verify_bundle(options)
        else:
            result = verify(options)
    except Rejection as error:
        result = error.diagnostic()
    except (ValueError, OSError) as error:
        result = Rejection("INPUT_ERROR", str(error)).diagnostic()
    except subprocess.SubprocessError as error:
        result = Rejection("UNVERIFIED", str(error)).diagnostic()
    if json_output:
        print(json.dumps(result, ensure_ascii=False))
    elif result["status"] == "PREPARED":
        print(f"PREPARED: {result['bundle']}")
    elif result["status"] != "VERIFIED":
        print(f"{result['status']}: {result['message']}")
    return 0 if result["status"] in ("VERIFIED", "PREPARED") else 1
