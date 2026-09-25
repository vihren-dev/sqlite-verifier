"""One-script offline verification; source elaboration alone never means VERIFIED."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from collections.abc import Sequence

from .diagnostics import Rejection
from .baseline import check_baseline
from .runtime import Runtime
from .profiles import profile
from .sandbox import SandboxUnavailable, run_sandboxed
from .sql_model import sql_inputs
from .sql_tree import parse
from .translate import starting_schema, statements


class Arguments(argparse.ArgumentParser):
    """Render usage failures using the same diagnostic protocol as later failures."""

    def error(self, message: str) -> None:
        """Keep missing flags, including profile, distinguishable from unproved obligations."""
        raise Rejection("INPUT_ERROR", message)


def arguments(values: Sequence[str]) -> argparse.Namespace:
    """Expose the seven contract inputs and optional inspection/output formatting."""
    parser = Arguments(prog="migration-check", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True, parser_class=Arguments)
    verify = commands.add_parser("verify", help="Check one migration under approved Lean requirements")
    verify.add_argument("--profile", required=True,
                        help="Exact SQLite semantic version: 3.51.0 or 3.46.0")
    for name in ("schema", "interpretation", "migration", "next-interpretation", "requirements", "proofs"):
        verify.add_argument("--" + name, required=True, type=Path)
    verify.add_argument("--format", choices=("human", "json"), default="human")
    verify.add_argument("--artifacts", type=Path, help="Create a directory with generated SQL and input hashes")
    verify.add_argument("--approved-baseline", type=Path, help="Require unchanged approved source/dependency hashes")
    return parser.parse_args(values)


def read_sql(path: Path) -> bytes:
    """Bound input before allocation while preserving the exact bytes the parser checks."""
    with path.open("rb") as stream:
        sql = stream.read(1024 * 1024 + 1)
    if len(sql) > 1024 * 1024:
        raise Rejection("UNVERIFIED", "SQL exceeds the 1 MiB parser limit", source=str(path))
    return sql


def verify(options: argparse.Namespace) -> dict[str, object]:
    """Seal SQL and approved sources, compile in isolation, and invoke the independent gate."""
    selected = profile(options.profile)
    runtime = Runtime.locate(selected.engine)
    schema_bytes, migration_bytes = read_sql(options.schema), read_sql(options.migration)
    schema = starting_schema(parse(runtime.parser, schema_bytes, str(options.schema), selected.engine))
    script = statements(parse(runtime.parser, migration_bytes, str(options.migration), selected.engine))
    if not script:
        raise Rejection("INPUT_ERROR", "Migration must contain at least one statement", source=str(options.migration))
    from .compile import CompileError, EXPECTED_SOURCE, compile_project

    generated = sql_inputs(schema, script, selected)
    if options.artifacts is not None:
        options.artifacts.mkdir(parents=True, exist_ok=False)
        (options.artifacts / "SqlInputs.lean").write_text(generated, encoding="utf-8")
        (options.artifacts / "Generated.lean").write_text(EXPECTED_SOURCE, encoding="utf-8")
    with TemporaryDirectory(prefix="migration-check-") as temporary:
        workspace = Path(temporary).resolve()
        try:
            compiled = compile_project(
                sysroot=runtime.sysroot, library=runtime.library, requirements=options.requirements,
                interpretation=options.interpretation, next_interpretation=options.next_interpretation,
                proofs=options.proofs, sql_inputs=generated, workspace=workspace)
        except CompileError as error:
            raise Rejection("UNVERIFIED", str(error)) from error
        hashes = dict(compiled.hashes)
        hashes.update({"schema.sql": hashlib.sha256(schema_bytes).hexdigest(),
                       "migration.sql": hashlib.sha256(migration_bytes).hexdigest(),
                       "profile": selected.engine})
        if options.approved_baseline is not None:
            check_baseline(options.approved_baseline, hashes)
        if options.artifacts is not None:
            (options.artifacts / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n", encoding="utf-8")
        output = workspace / "gate-output"
        output.mkdir()
        checked = run_sandboxed(
            [str(runtime.checker), str(runtime.library), str(compiled.trusted), str(compiled.candidate)],
            read_roots=[*runtime.read_roots(), compiled.trusted, compiled.candidate],
            write_root=output, environment={"LEAN_SYSROOT": str(runtime.sysroot)}, timeout=30)
        if checked.returncode == 2:
            raise Rejection("VIOLATED", "A kernel-checked argument refutes the supplied verification contract")
        if checked.returncode != 0:
            raise Rejection("UNVERIFIED", checked.stderr.strip() or "Independent kernel gate rejected the proof")
    return {"status": "VERIFIED", "profile": hashes["profile"], "statements": len(script), "inputs": hashes}


def main(values: Sequence[str]) -> int:
    """Return zero exactly for an independently accepted proof, with optional JSON diagnostics."""
    json_output = any(tuple(values[index:index + 2]) == ("--format", "json") for index in range(len(values)))
    json_output = json_output or "--format=json" in values
    try:
        result = verify(arguments(values))
    except Rejection as error:
        result = error.diagnostic()
    except (ValueError, OSError) as error:
        result = Rejection("INPUT_ERROR", str(error)).diagnostic()
    except (subprocess.SubprocessError, SandboxUnavailable) as error:
        result = Rejection("UNVERIFIED", str(error)).diagnostic()
    if json_output:
        print(json.dumps(result, ensure_ascii=False))
    elif result["status"] != "VERIFIED":
        print(f"{result['status']}: {result['message']}")
    return 0 if result["status"] == "VERIFIED" else 1
