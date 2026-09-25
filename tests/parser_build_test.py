"""Cheap build orchestration tests; fake tools never compile the large amalgamations."""

import hashlib
import json
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "parser"))
import build
import build_cache
IMMUTABLE = build_cache.immutable


class IncrementalBuildTests(unittest.TestCase):
    """Exercise complete successful builds and failures with deterministic tiny outputs."""

    def setUp(self) -> None:
        """Create two independent pinned source fixtures and a compiler identity."""
        folder = TemporaryDirectory(prefix="parser-build-test-")
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        parser = self.root / "parser"
        parser.mkdir()
        for name in ("build.py", "build_cache.py", "generate.py", "main.c", "runtime.h", "tokenizer.c"):
            (parser / name).write_text(name)
        for source in ("upstream", "upstream-3.46.0"):
            upstream = parser / source
            upstream.mkdir()
            for name in ("lemon.c", "lempar.c", "parse.y", "sqlite3.h"):
                (upstream / name).write_text(name)
            (upstream / "sqlite3.c").write_text("#define TK_ID 1\n")
            self.pin(upstream)
        self.compiler = self.root / "cc"
        self.compiler.write_text("compiler-one")
        self.compiler.chmod(0o755)
        self.enterContext(patch.object(build, "ROOT", self.root))
        self.enterContext(patch.dict(os.environ, {"CC": str(self.compiler), "PATH": "/bin"}, clear=True))
        # Production caches only immutable Nix tools; this fixture simulates that identity.
        self.enterContext(patch.object(build_cache, "immutable", return_value=True))
        self.commands = self.enterContext(patch.object(build, "run", side_effect=self.tool))

    def pin(self, upstream: Path) -> None:
        """Update reviewed fixture pins separately from deliberate source tampering."""
        hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in upstream.iterdir() if path.name != "sha256.json"}
        (upstream / "sha256.json").write_text(json.dumps(hashes))

    def tool(self, arguments: list[str]) -> str:
        """Produce the exact files each real compiler/Lemon invocation promises."""
        if "-o" in arguments:
            target = Path(arguments[arguments.index("-o") + 1])
            target.write_text("compiled:" + " ".join(arguments))
            target.chmod(0o755)
        elif "-E" in arguments:
            return "%left ID.\n"
        elif "-g" in arguments:
            return "input ::= ID.\n"
        else:
            directory = Path(arguments[0]).parent
            name = "parse" if arguments[-1].endswith("parse.y") else "syntax"
            (directory / f"{name}.c").write_text("generated C")
            (directory / f"{name}.h").write_text("#define TK_ID 1\n")
        return ""

    def build(self, old: bool = False) -> None:
        """Invoke the real orchestration against one of the fake pinned releases."""
        build.build("3.46.0" if old else "3.51.0", "upstream-3.46.0" if old else "upstream",
                    "sqlite-parser-3.46.0" if old else "sqlite-parser")

    def test_noop_and_independent_release_sources(self) -> None:
        """No-op builds invoke no tool, and one release's source never dirties the other."""
        self.build(); self.build(True)
        self.commands.reset_mock()
        self.build(); self.build(True)
        self.commands.assert_not_called()
        with patch.dict(os.environ, {"NIX_BUILD_TOP": "/tmp/new-session", "NIX_LOG_FD": "12"}):
            self.build(); self.build(True)
            self.commands.assert_not_called()
        upstream = self.root / "parser/upstream-3.46.0"
        (upstream / "parse.y").write_text("reviewed new grammar fixture")
        self.pin(upstream)
        self.build()
        self.commands.assert_not_called()
        self.build(True)
        self.assertTrue(self.commands.called)

    def test_changed_sources_generator_compiler_and_flags(self) -> None:
        """Source and tool changes invalidate content stamps even without timestamp reliance."""
        self.build()
        paths = [self.root / "parser" / name for name in
                 ("main.c", "runtime.h", "tokenizer.c", "generate.py", "build.py", "build_cache.py")]
        for path in [*paths, self.compiler]:
            with self.subTest(path=path.name):
                path.write_text(path.read_text() + " changed")
                self.commands.reset_mock(); self.build()
                self.assertTrue(self.commands.called)
                self.commands.reset_mock(); self.build()
                self.commands.assert_not_called()
        with patch.dict(os.environ, {"NIX_CFLAGS_COMPILE": "-O2"}):
            self.commands.reset_mock(); self.build()
            self.assertTrue(self.commands.called)
            self.commands.reset_mock(); self.build()
            self.commands.assert_not_called()
        replacement = self.root / "other-cc"
        replacement.write_bytes(self.compiler.read_bytes())
        replacement.chmod(0o755)
        with patch.dict(os.environ, {"CC": str(replacement)}):
            self.commands.reset_mock(); self.build()
            self.assertTrue(self.commands.called)
        self.build()  # Restore the original compiler before changing only the SDK target.
        with patch.dict(os.environ, {"MACOSX_DEPLOYMENT_TARGET_arm64_apple_darwin": "15.0"}):
            self.commands.reset_mock(); self.build()
            self.assertTrue(self.commands.called)
            self.commands.reset_mock(); self.build()
            self.commands.assert_not_called()

    def test_missing_modified_outputs_and_tampering(self) -> None:
        """Every intermediate is required, and a hit never bypasses upstream verification."""
        self.build(); self.build(True)
        directory = self.root / "build/parser"
        outputs = [path for path in directory.iterdir() if path.name != "build-state.json"]
        outputs.append(self.root / "build/sqlite-parser")
        for path in outputs:
            with self.subTest(output=path.name):
                path.unlink()
                self.commands.reset_mock(); self.build(True)
                self.commands.assert_not_called()
                self.build(); self.assertTrue(self.commands.called)
        outputs[-1].write_text("corrupted executable")
        self.commands.reset_mock(); self.build()
        self.assertTrue(self.commands.called)
        (directory / "build-state.json").write_text("incomplete JSON")
        self.commands.reset_mock(); self.build()
        self.assertTrue(self.commands.called)
        for old in (False, True):
            source = "upstream-3.46.0" if old else "upstream"
            (self.root / "parser" / source / "sqlite3.c").write_text("unpinned replacement")
            self.commands.reset_mock()
            with self.assertRaisesRegex(ValueError, "Pinned upstream file changed"):
                self.build(old)
            self.commands.assert_not_called()

    def test_unpinned_compiler_and_failed_build_never_reuse(self) -> None:
        """Unknown toolchains and interrupted builds cannot produce a valid hit."""
        self.build()
        with patch.object(build_cache, "immutable", return_value=False):
            for _ in range(2):
                self.commands.reset_mock(); self.build()
                self.assertTrue(self.commands.called)
        with patch.object(build, "run", side_effect=RuntimeError("tool failed")):
            with self.assertRaisesRegex(RuntimeError, "tool failed"):
                self.build()
        self.assertFalse((self.root / "build/parser/build-state.json").exists())
        self.commands.reset_mock(); self.build()
        self.assertTrue(self.commands.called)

    def test_mutable_toolchain_overrides_disable_reuse(self) -> None:
        """Only ordinary immutable Nix search flags justify skipping compilation."""
        store = "/nix/store/" + "1" * 32 + "-fixture"
        with patch.object(build_cache, "immutable", IMMUTABLE):
            self.assertTrue(build_cache.stable_environment({"NIX_CFLAGS_COMPILE":
                f"-frandom-seed=abc -isystem {store}/include -fmacro-prefix-map={store}={store}"}))
            for environment in ({"CPATH": "/tmp/include"}, {"SDKROOT": "/mutable/sdk"},
                    {"CPATH": store + ":"}, {"NIX_DYNAMIC_LINKER": "/tmp/ld.so"},
                    {"DEVELOPER_DIR_arm64_apple_darwin": "/mutable/sdk"},
                    {"NIX_CFLAGS_COMPILE": "@options"}, {"NIX_LDFLAGS": "-Wl,-T,local"},
                    {"NIX_CFLAGS_COMPILE": f"-I{store}/../../mutable"},
                    {"NIX_ENFORCE_PURITY": "1"}):
                self.assertFalse(build_cache.stable_environment(environment), environment)


if __name__ == "__main__":
    unittest.main()
