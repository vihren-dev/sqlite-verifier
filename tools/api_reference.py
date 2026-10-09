"""Generate the public Lean reference with placeholder source links and check its local links.

`tools/api_reference_links.py` puts the checked commit into the links in a cheap later step."""

import argparse
from html import escape
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.source_revision import FULL_COMMIT_HASH_PATTERN

SOURCE_REPOSITORY = "https://github.com/vihren-dev/sqlite-verifier"
"""Source links identify the public repository and the caller's checked commit."""
SOURCE_REVISION_PLACEHOLDER = "SOURCE-REVISION"
"""The commit in base-build source links; not hexadecimal, so it cannot be a commit hash."""
COMMAND_TIMEOUT_SECONDS = 600
"""Bound each documentation subprocess, including the Lean core prepass."""
CORE_DOCUMENTATION_PREFIXES = ("Init", "Std")
"""The public library imports Init and Std; their pages supply checked type links."""
TOP_FRAGMENT = "top"
"""HTML defines this fragment as document start, even without an element ID.

See https://html.spec.whatwg.org/multipage/browsing-the-web.html#the-indicated-part-of-the-document.
"""
OMITTED_RECURSOR_SUFFIXES = frozenset({"rec", "ndrec", "recOn", "ndrecOn", "casesOn"})
"""doc-gen4 omits these generated recursors; their links refer to the parent type."""
CORE_MODULE_LINK_CORRECTIONS = {"Init/Tactic.html": "Init/Tactics.html"}
"""Correct the Lean 4.34.1 TacticsExtra module docstring's nonexistent local page."""


class PageLinks(HTMLParser):
    """Collect HTML targets and references so an artifact can be checked without a server."""

    def __init__(self) -> None:
        """Initialize one page's IDs and href/src links."""
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Read link-bearing attributes and anchors from a generated page."""
        for name, value in attrs:
            if value is not None and (name == "id" or (tag == "a" and name == "name")):
                self.ids.add(value)
            if value is not None and name in {"href", "src"}:
                self.links.append(value)


def public_sources(root: Path) -> list[Path]:
    """Enumerate the entry point and library source files selected by the Nix fileset."""
    return [root / "SqliteVerifier.lean", *sorted((root / "SqliteVerifier").rglob("*.lean"))]


def source_revision(revision: str) -> str:
    """Reject ambiguous source references before generating any public link."""
    if re.fullmatch(FULL_COMMIT_HASH_PATTERN, revision) is None:
        raise ValueError(f"Invalid API reference --revision {revision!r}; use just reference FULL_COMMIT_HASH")
    return revision


def correct_reference_links(output: Path) -> int:
    """Route omitted recursors to existing parent anchors and correct the pinned core page typo."""
    output = output.resolve()
    pages: dict[Path, PageLinks] = {}
    for path in output.rglob("*.html"):
        page = PageLinks()
        page.feed(path.read_text())
        pages[path] = page
    corrected = 0
    for origin, page in pages.items():
        replacements: dict[str, str] = {}
        for link in page.links:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc:
                continue
            target = (origin.parent / unquote(parsed.path)).resolve() if parsed.path else origin
            if not target.is_relative_to(output):
                continue
            replacement = parsed
            if not target.is_file():
                corrected_path = CORE_MODULE_LINK_CORRECTIONS.get(target.relative_to(output).as_posix())
                if corrected_path is not None and (output / corrected_path) in pages:
                    target = output / corrected_path
                    replacement = replacement._replace(path=os.path.relpath(target, origin.parent))
            fragment = unquote(parsed.fragment)
            parent, separator, suffix = fragment.rpartition(".")
            if (target in pages and fragment not in pages[target].ids
                    and parsed.fragment not in pages[target].ids and separator
                    and suffix in OMITTED_RECURSOR_SUFFIXES and parent in pages[target].ids):
                replacement = replacement._replace(fragment=quote(parent, safe="."))
            if replacement != parsed:
                replacements[link] = replacement.geturl()
        if replacements:
            text = origin.read_text()
            for old, new in replacements.items():
                attribute = f'href="{escape(old, quote=True)}"'
                count = text.count(attribute)
                if not count:
                    raise ValueError(f"Reference link format differs in {origin}; inspect the generator update")
                text = text.replace(attribute, f'href="{escape(new, quote=True)}"')
                corrected += count
            origin.write_text(text)
    return corrected


def generate_reference(root: Path, executable: Path, build: Path) -> None:
    """Use the pinned CLI directly, without a Git checkout or Lake source facets. Source links
    contain the placeholder, so the result depends only on the Lean sources and pinned tools."""
    revision = SOURCE_REVISION_PLACEHOLDER
    build.mkdir(parents=True, exist_ok=True)

    def run(*arguments: str) -> None:
        """Retain Lake's source import environment for a bounded documentation command."""
        subprocess.run(["lake", "env", str(executable), *arguments], cwd=root,
                       check=True, timeout=COMMAND_TIMEOUT_SECONDS)

    run("bibPrepass", "--build", str(build), "--none")
    for module in CORE_DOCUMENTATION_PREFIXES:
        run("genCore", "--build", str(build), module, "api-docs.db")
    modules: list[str] = []
    for source in public_sources(root):
        relative = source.relative_to(root)
        module = ".".join(relative.with_suffix("").parts)
        modules.append(module)
        uri = f"{SOURCE_REPOSITORY}/blob/{revision}/{relative.as_posix()}"
        run("single", "--build", str(build), module, "api-docs.db", uri)
    run("fromDb", "--build", str(build), "--manifest", str(build / "manifest.json"),
        str(build / "api-docs.db"), *modules)
    corrected = correct_reference_links(build / "doc")
    report = validate_reference(build / "doc", root, revision)
    report["corrected_links"] = corrected
    (build / "doc/reference-check.json").write_text(json.dumps(report, indent=2) + "\n")


def validate_reference(output: Path, root: Path, revision: str) -> dict[str, int | str]:
    """Require all public pages, exact source links (commit or placeholder) and valid local targets."""
    if revision != SOURCE_REVISION_PLACEHOLDER:
        revision = source_revision(revision)
    output = output.resolve()
    pages: dict[Path, PageLinks] = {}
    for path in output.rglob("*.html"):
        page = PageLinks()
        page.feed(path.read_text())
        pages[path] = page
    declarations = 0
    sources = public_sources(root)
    for source in sources:
        relative = source.relative_to(root)
        page = output / relative.with_suffix(".html")
        if page not in pages:
            raise ValueError(f"Public reference page is missing: {page}; rebuild the reference")
        module = ".".join(relative.with_suffix("").parts)
        data = json.loads((output.parent / "doc-data" / f"declaration-data-{module}.bmp").read_text())
        prefix = f"{SOURCE_REPOSITORY}/blob/{revision}/{relative.as_posix()}#L"
        for declaration in data["declarations"]:
            if not declaration["info"]["sourceLink"].startswith(prefix):
                raise ValueError(f"Reference source link differs for {module}; rebuild with the checked commit")
            declarations += 1
    links = 0
    for origin, page in pages.items():
        for link in page.links:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc:
                continue
            target = (origin.parent / unquote(parsed.path)).resolve() if parsed.path else origin
            if target.is_dir():
                target /= "index.html"
            if not target.is_relative_to(output) or not target.is_file():
                raise ValueError(f"Reference link is missing: {origin}: {link}; rebuild the reference")
            fragment = unquote(parsed.fragment)
            is_top = fragment.isascii() and fragment.lower() == TOP_FRAGMENT
            if (parsed.fragment and target in pages and not is_top
                    and parsed.fragment not in pages[target].ids and fragment not in pages[target].ids):
                raise ValueError(f"Reference anchor is missing: {origin}: {link}; inspect the declaration link")
            links += 1
    return {"public_modules": len(sources), "public_declarations": declarations,
            "html_pages": len(pages), "local_links": links}


def main() -> None:
    """Accept Nix's explicit tool and source directory; the commit comes later."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    arguments = parser.parse_args()
    generate_reference(arguments.root.resolve(), arguments.executable.resolve(), arguments.build.resolve())


if __name__ == "__main__":
    main()
