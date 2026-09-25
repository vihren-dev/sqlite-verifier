"""Check local destinations in authored Markdown without downloading linked pages."""

from pathlib import Path
import re
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


if __name__ == "__main__":
    failures = broken_links(ROOT)
    if failures:
        raise SystemExit("\n".join(failures))
    print("Authored Markdown local file links resolve; external URLs/anchors are not checked.")
