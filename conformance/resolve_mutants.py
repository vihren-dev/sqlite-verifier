"""Mutants of name resolution and transaction control, built as changed copies of the model.

ADR 0008 ("How `resolve` is tested", Mutants) requires that each listed change of
`resolve` makes at least one conformance case change its verdict, so that the
suite is known to test each rule. Resolution functions are called through dot
notation (`catalog.find`), so a copy of single definitions in a private namespace
would still call the originals. Each mutant is therefore a real copy of the
`belay-sqlite-model` and `verifier-conformance` packages with one text change, which Lake
rebuilds from one shared base build. The build covers only the import closure of
`VerifierConformance.Classify`, which does not import the law modules, so a mutant that
breaks a law still builds. The Lean interpreter then classifies the cases, given as the
Lean terms that the conformance runner emits, with the mutant's `classifyCase`.

The authored model cases must all agree, so a mutant is killed when any case
gets another verdict: `DISAGREE`, or `MODEL_UNSUPPORTED` where the mutant moves
an agreeing case out of the model's scope.
"""

from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.model_check import compiled_many

SQLITE = "belay-sqlite-model/Belay/Sqlite/Model/"
"""The model sources, relative to `packages/`."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "non_ascii_fold": (SQLITE + "Identifier.lean",
        "def Identifier.folded (name : Identifier) : List UInt8 := name.bytes.map lowerAscii",
        "def Identifier.folded (name : Identifier) : List UInt8 :=\n"
        "  name.bytes.map fun byte => if 0x80 ≤ byte && byte ≤ 0x9e && byte != 0x97 then byte + 32 else lowerAscii byte"),
    "affinity_order": (SQLITE + "Resolution/TypeAffinity.lean",
        'if containsText upper "INT" then .integer\n    else if ["CHAR", "CLOB", "TEXT"].any (containsText upper) then .text',
        'if ["CHAR", "CLOB", "TEXT"].any (containsText upper) then .text\n    else if containsText upper "INT" then .integer'),
    "desc_rowid_alias": (SQLITE + "Resolution/Definitions.lean",
        "aliasesRowid (reportedType definition.declaredType) && !descending", "aliasesRowid (reportedType definition.declaredType)"),
    "rollback_keeps_catalog": (SQLITE + "Resolution/Resolve.lean",
        "{ state with catalog := state.saved.getD state.catalog, saved := none }",
        "{ state with catalog := state.catalog, saved := none }"),
    "table_index_same_name": (SQLITE + "Resolution/Definitions.lean",
        "  | some (_, { entry := .index _, .. }) => prepareError catalog (.indexNameUsed name)\n"
        "  | some (_, { entry := .trigger _, .. }) | none =>",
        "  | some (_, { entry := .index _, .. }) | some (_, { entry := .trigger _, .. }) | none =>"),
    "constant_column_limit": (SQLITE + "Resolution/AddColumn.lean",
        "table.columns.length + 1 > context.profile.limits.columns", "table.columns.length + 1 > 2000"),
    "no_table_exists": (SQLITE + "Resolution/Definitions.lean",
        "  | some (_, { entry := .table _, .. }) => prepareError catalog (.tableExists name)\n"
        "  | some (_, { entry := .index _, .. }) => prepareError catalog (.indexNameUsed name)\n"
        "  | some (_, { entry := .trigger _, .. }) | none =>",
        "  | some (_, { entry := .index _, .. }) => prepareError catalog (.indexNameUsed name)\n"
        "  | some (_, { entry := .table _, .. }) | some (_, { entry := .trigger _, .. }) | none =>"),
    "no_too_many_columns": (SQLITE + "Resolution/AddColumn.lean",
        "    else if table.columns.length + 1 > context.profile.limits.columns then\n"
        "      prepareError catalog (.expression (.tooManyColumns tableName))\n", ""),
    "no_duplicate_column": (SQLITE + "Resolution/AddColumn.lean",
        "    else if (columnPosition table.columns definition.name).isSome then\n"
        "      prepareError catalog (.expression (.duplicateColumn definition.name))\n", ""),
    "no_such_table": (SQLITE + "Resolution/AddColumn.lean",
        "  | none => prepareError catalog (.noSuchTable tableName)\n  | some (position, table) =>\n"
        "    if reservedName tableName then prepareError catalog (.expression (.tableMayNotBeAltered tableName))",
        "  | none => restrict [] .engineTable\n  | some (position, table) =>\n"
        "    if reservedName tableName then prepareError catalog (.expression (.tableMayNotBeAltered tableName))"),
    "commit_without_transaction": (SQLITE + "StatementStep.lean",
        "    | none => .halt (.failure position .noActiveTransaction state.database)\n"
        "    | some _ => .next { state with snapshot := none }",
        "    | none => .next state\n    | some _ => .next { state with snapshot := none }"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. A removed prepare-error condition lets the statement continue where
the match allows it (`no_table_exists` creates the table again), or makes it a
model restriction where nothing can continue (`no_such_table`)."""

GUARDS: dict[str, str] = {
    "non_ascii_fold": "rule:Identifier.folded",
    "affinity_order": "rule:affinityOf",
    "desc_rowid_alias": "rule:applyConstraint",
    "rollback_keeps_catalog": "rule:resolveStatement",
    "table_index_same_name": "rule:resolveCreateTable",
    "constant_column_limit": "rule:resolveAddColumn",
    "no_table_exists": "rule:resolveCreateTable",
    "no_too_many_columns": "rule:resolveAddColumn",
    "no_duplicate_column": "rule:resolveAddColumn",
    "no_such_table": "rule:resolveAddColumn",
    "commit_without_transaction": "rule:advanceWith",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""

BUILD_TIMEOUT_SECONDS = 600
"""One Lake build of a copy; a fresh base build takes about 12 seconds."""
RUN_TIMEOUT_SECONDS = 300
"""One interpreted classification of all case terms."""
AGREE = "Belay.Sqlite.Model.Conformance.Verdict.agree"
"""The printed verdict of an agreeing case."""
UNSUPPORTED = "Belay.Sqlite.Model.Conformance.Verdict.modelUnsupported"
"""The printed verdict of a case outside the model's scope, such as a boundary case of an obligation."""
MAX_REC_DEPTH = 100000
"""Lean's `maxRecDepth` for elaborating the case terms, as the kernel proofs of the cases use."""


def classifier(terms: list[str]) -> str:
    """A Lean program that prints the verdict of each case term, one per line. Each term is
    its own definition, so Lean's heartbeat limit, which applies to one declaration, bounds
    the elaboration of one case and not of all of them."""
    definitions = "".join(f"def case{index} : Case :=\n  " + term.replace("\n", "\n  ") + "\n"
                          for index, term in enumerate(terms))
    names = ", ".join(f"case{index}" for index in range(len(terms)))
    return ("import VerifierConformance.Classify\nopen Belay.Sqlite.Model Belay.Sqlite.Model.Conformance\n"
            f"set_option maxRecDepth {MAX_REC_DEPTH}\n"
            f"{definitions}def cases : List Case := [{names}]\n"
            "def main : IO Unit := for c in cases do IO.println (reprStr (classifyCase c))\n")


def run(arguments: list[str], cwd: Path, lean: Path, timeout: float) -> str:
    """Run a toolchain command with only the pinned Lean on the path; raise with its output on failure."""
    result = subprocess.run(arguments, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False,
                            env={**os.environ, "PATH": f"{lean / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}",
                                 "HOME": str(cwd)})
    if result.returncode:
        raise RuntimeError(f"{' '.join(arguments)} failed in {cwd}: {result.stdout}{result.stderr}")
    return result.stdout


def verdicts(packages: Path, lean: Path, program: str) -> list[str]:
    """Build the case classification of the copy and print one verdict for each case."""
    conformance = packages / "verifier-conformance"
    run(["lake", "build", "VerifierConformance.Classify"], conformance, lean, BUILD_TIMEOUT_SECONDS)
    (conformance / "Classify.lean").write_text(program)
    return run(["lake", "env", "lean", "--run", "Classify.lean"], conformance, lean, RUN_TIMEOUT_SECONDS).splitlines()


def mutate(base: Path, root: Path, name: str, change: tuple[str, str, str], lean: Path, program: str) -> list[str]:
    """Copy the built base, apply one mutant's change, and classify the cases with it."""
    target, before, after = change
    copy = root / name
    shutil.copytree(base, copy, symlinks=True)
    source = copy / target
    text = source.read_text()
    if text.count(before) != 1:
        raise ValueError(f"Mutant {name} does not match exactly one place in {target}; update its text")
    source.write_text(text.replace(before, after))
    return verdicts(copy, lean, program)


def measure(cases: list[dict[str, Json]], repository: Path, runtime: Path,
            mutants: dict[str, tuple[str, str, str]] = MUTANTS,
            targets: dict[str, tuple[str, ...]] | None = None, expected: str = AGREE) -> dict[str, Json]:
    """Classify the cases with the unchanged model and with each of `mutants`, in parallel.
    `runtime` is the conformance runtime: its runner emits the case terms, and its
    `lean` folder is the pinned toolchain. Every case must have the `expected` verdict
    with the unchanged model: `AGREE` for coverage cases, `UNSUPPORTED` for boundary cases. With `targets`, a mutant copy classifies only the cases that its entry names,
    which keeps the elaboration of case terms short; without it, every case."""
    lean = runtime / "lean"
    terms = [str(answer["caseLean"]) for answer in compiled_many(cases, runtime, emit_lean=True)]
    names = [str(case["provenance"][0][1]) for case in cases]
    selected = {name: [index for index, case in enumerate(names) if targets is None or case in targets[name]]
                for name in mutants}
    missing = [name for name, indexes in selected.items() if not indexes]
    if missing:
        raise ValueError(f"Mutants without a target case among the cases: {missing}; name an existing case")
    with TemporaryDirectory(prefix="resolve-mutants-") as directory:
        root = Path(directory)
        base = root / "base"
        for package in ("belay-sqlite-model", "verifier-conformance"):
            shutil.copytree(repository / "packages" / package, base / package,
                            ignore=shutil.ignore_patterns(".lake", "build"))
        original = verdicts(base, lean, classifier(terms))
        if original != [expected] * len(cases):
            raise ValueError(f"Every case must be {expected} with the unchanged model before mutation: {original}")
        with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
            results = dict(zip(mutants, pool.map(
                lambda name: mutate(base, root, name, mutants[name], lean,
                                    classifier([terms[index] for index in selected[name]])), mutants)))
    return {name: {"killed": any(verdict != expected for verdict in found),
                   "changed": {names[index]: verdict for index, verdict in zip(selected[name], found, strict=True)
                               if verdict != expected}}
            for name, found in results.items()}
