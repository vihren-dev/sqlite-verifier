"""Content stamps for the declared immutable toolchain; no compiler runs on cache hits."""

import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sys

ENVIRONMENT = {
    "CC", "PATH", "CFLAGS", "CPPFLAGS", "LDFLAGS", "CPATH", "C_INCLUDE_PATH",
    "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH", "LIBRARY_PATH", "COMPILER_PATH",
    "GCC_EXEC_PREFIX", "SDKROOT", "DEVELOPER_DIR", "MACOSX_DEPLOYMENT_TARGET",
    "SOURCE_DATE_EPOCH", "CCC_OVERRIDE_OPTIONS", "CLANG_CONFIG_FILE_SYSTEM_DIR",
    "CLANG_CONFIG_FILE_USER_DIR",
}
SEARCH_PATHS = {"CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH",
                "LIBRARY_PATH", "COMPILER_PATH", "GCC_EXEC_PREFIX", "SDKROOT", "DEVELOPER_DIR"}

NIX_PREFIXES = ("NIX_CC", "NIX_BINTOOLS", "NIX_CFLAGS", "NIX_LDFLAGS",
                "NIX_DYNAMIC_LINKER", "NIX_HARDENING", "NIX_ENFORCE", "NIX_DONT",
                "NIX_IGNORE", "NIX_NO_SELF", "NIX_APPLE_SDK", "NIX_STORE", "NIX_LINK_TYPE")


def digest(path: Path) -> str:
    """Stream large amalgamations without allocating another full source copy."""
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def immutable(path: str) -> bool:
    """Only immutable Nix package identities justify reusing a compiler's transitive tools."""
    return (".." not in Path(path).parts and
            re.match(r"^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/]+(?:/|$)", path) is not None)


def stable_environment(environment: dict[str, str]) -> bool:
    """Mutable include/library/SDK overrides conservatively disable reuse."""
    for name in SEARCH_PATHS:
        if name in environment and any(not immutable(path) for path in environment[name].split(os.pathsep)):
            return False
    for name in ("NIX_CC", "NIX_BINTOOLS"):
        if environment.get(name) and not immutable(environment[name]):
            return False
    if any(environment.get(name) for name in
           ("CCC_OVERRIDE_OPTIONS", "CLANG_CONFIG_FILE_SYSTEM_DIR", "CLANG_CONFIG_FILE_USER_DIR")):
        return False
    if environment.get("NIX_ENFORCE_PURITY") == "1":
        return False  # Purity checks depend on the transient build directory.
    for name, value in environment.items():
        if name.startswith("DEVELOPER_DIR_") and not immutable(value):
            return False
        if name.startswith("NIX_DYNAMIC_LINKER") and value and not immutable(value):
            return False
        if not name.startswith(("NIX_CFLAGS", "NIX_LDFLAGS")):
            continue
        for token in shlex.split(value):
            if immutable(token) or token in ("-isystem", "-I", "-L", "-rpath", "-rpath-link"):
                continue
            if token.startswith(("-I", "-L")) and immutable(token[2:]):
                continue
            if re.fullmatch(r"-frandom-seed=[a-zA-Z0-9]+|-O[0-3sgz]", token):
                continue
            # The destination is substituted text, not an input path (Nix uses eeee...).
            if token.startswith("-fmacro-prefix-map=") and len(token.split("=")) == 3 and immutable(
                    token.split("=")[1]):
                continue
            return False  # Unknown compiler overrides remain usable, but never cached.
    return True


def identity(root: Path, upstream: Path, version: str, executable: str) -> tuple[str, str, bool]:
    """Bind source, generator, fixed command flags and actual selected compiler identity."""
    cc = os.environ.get("CC", "cc")
    selected = shutil.which(cc)
    if selected is None:
        raise FileNotFoundError(f"Parser compiler is not executable: {cc}")
    compiler = Path(selected).resolve()
    environment = {name: value for name, value in os.environ.items()
                   if name in ENVIRONMENT or name.startswith(
                       NIX_PREFIXES + ("DEVELOPER_DIR_", "MACOSX_DEPLOYMENT_TARGET_"))}
    sources = [root / "parser" / name for name in
               ("build.py", "build_cache.py", "generate.py", "main.c", "runtime.h", "tokenizer.c")]
    sources.extend(upstream / name for name in ("sha256.json", "lemon.c", "lempar.c", "parse.y", "sqlite3.c", "sqlite3.h"))
    data = {"version": version, "executable": executable, "compiler": str(compiler),
            "selected_compiler": selected, "compiler_sha256": digest(compiler),
            "python": [sys.executable, sys.version, digest(Path(sys.executable).resolve())],
            "environment": environment,
            "sources": {str(path): digest(path) for path in sources}}
    stamp = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
    return cc, stamp, immutable(str(compiler)) and stable_environment(environment)


def output_hashes(outputs: list[Path]) -> dict[str, str] | None:
    """Missing, incomplete or modified intermediates and executables invalidate reuse."""
    if not all(path.is_file() for path in outputs):
        return None
    return {str(path): f"{digest(path)}:{path.stat().st_mode}" for path in outputs}


def current(stamp: Path, inputs: str, outputs: list[Path]) -> bool:
    """A corrupted or interrupted stamp is a cache miss, never build success."""
    hashes = output_hashes(outputs)
    if hashes is None:
        return False
    try:
        return json.loads(stamp.read_text()) == {"inputs": inputs, "outputs": hashes}
    except (OSError, ValueError):
        return False


def record(stamp: Path, inputs: str, outputs: list[Path]) -> None:
    """Publish the successful state only after every expected output exists."""
    hashes = output_hashes(outputs)
    if hashes is None:
        raise RuntimeError("Parser build did not produce every expected output")
    temporary = stamp.with_suffix(".tmp")
    temporary.write_text(json.dumps({"inputs": inputs, "outputs": hashes}, sort_keys=True) + "\n")
    temporary.replace(stamp)
