"""Check local destinations in authored Markdown without downloading linked pages."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def broken_links(root: Path) -> list[str]:
    """Validate file destinations, leaving external URLs and section anchors to human review."""
    errors: list[str] = []
    paths = [*root.glob("*.md"), *root.glob("docs/**/*.md"), *root.glob("plans/**/*.md"),
             *root.glob("examples/**/*.md")]
    for path in paths:
        for match in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", path.read_text()):
            target = match[1].split(' "', 1)[0].strip("<>")
            url = urlsplit(target)
            if not url.scheme and url.path and not url.path.startswith("/"):
                if not (path.parent / unquote(url.path)).exists():
                    errors.append(f"{path.relative_to(root)}: missing {target}")
    return errors


def test_broken_links_detects_missing_local_files(tmp_path: Path) -> None:
    """Missing local files are reported; external URLs and anchors are outside this bounded check."""
    (tmp_path / "README.md").write_text("[file](missing.md) [web](https://example.org) [anchor](#x)")
    assert broken_links(tmp_path) == ["README.md: missing missing.md"]
    (tmp_path / "missing.md").write_text("present")
    assert broken_links(tmp_path) == []
    (tmp_path / "docs/nested").mkdir(parents=True)
    (tmp_path / "docs/nested/guide.md").write_text("[broken](absent.md)")
    assert broken_links(tmp_path) == ["docs/nested/guide.md: missing absent.md"]


def test_local_markdown_links() -> None:
    """Every authored local Markdown destination resolves to an existing file."""
    assert broken_links(ROOT) == []


if __name__ == "__main__":
    failures = broken_links(ROOT)
    print("\n".join(failures) or "Authored Markdown local file links resolve; external URLs/anchors are not checked.")
    sys.exit(1 if failures else 0)
