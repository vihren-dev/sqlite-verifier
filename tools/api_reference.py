"""Add our public modules to the cached core documentation and write the API reference pages.

`build-support/api-reference-core.nix` builds the doc-gen4 database for Lean's `Init` and `Std`.
This tool adds our modules to a copy of it, writes the pages with placeholder source links, and
corrects the one known doc-gen4 link bug on our pages. `tools/api_reference_links.py` puts the
checked commit into the source links. ADR 0009 describes the split and why the build does not
check doc-gen4's output.
"""

import argparse
from html import escape
from html.parser import HTMLParser
import json
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
"""Bound each doc-gen4 command."""
CORE_DATABASE = "api-docs.db"
"""The doc-gen4 database that the core build creates and this tool extends."""
OMITTED_RECURSOR_SUFFIXES = frozenset({"rec", "ndrec", "recOn", "ndrecOn", "casesOn"})
"""Suffixes of internal names that doc-gen4 links to with a missing anchor.

doc-gen4 maps an internal name such as `Eq.ndrec` to its target type, but uses the internal name
as the link anchor (`#Eq.ndrec`), which only `#Eq` exists for. On our pages these are the `▸`
links in derived `decEq` equations. Reported upstream as
https://github.com/leanprover/doc-gen4/issues/423; remove the correction when it is fixed.
"""


class PageLinks(HTMLParser):
    """Collect the anchors and link targets of one generated page."""

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
    return [root / "SqliteVerifier.lean", *sorted((root / "SqliteVerifier").rglob("*.lean")),
            *sorted((root / "packages/belay-sqlite/Belay").rglob("*.lean"))]


def module_source_path(root: Path, source: Path) -> Path:
    """Map the model package source to its Lean module, retaining its repository path for links."""
    model = root / "packages/belay-sqlite"
    return source.relative_to(model) if source.is_relative_to(model) else source.relative_to(root)


def source_revision(revision: str) -> str:
    """Reject ambiguous source references before generating any public link."""
    if re.fullmatch(FULL_COMMIT_HASH_PATTERN, revision) is None:
        raise ValueError(f"Invalid API reference --revision {revision!r}; use just reference FULL_COMMIT_HASH")
    return revision


def our_pages(output: Path) -> list[Path]:
    """The pages of our public modules; the other pages document Lean's own libraries."""
    return sorted(path for path in output.rglob("*.html")
                  if path.relative_to(output).parts[0] in {"SqliteVerifier", "SqliteVerifier.html", "Belay"})


def correct_recursor_links(output: Path) -> int:
    """Point links on our pages to an omitted recursor at its parent type; return the count.

    A link is changed only when its anchor is missing on the target page, ends in a recursor
    suffix, and the parent anchor exists. An existing raw or decoded anchor wins. Only our pages
    and the pages that they link to are read.
    """
    output = output.resolve()
    cache: dict[Path, PageLinks] = {}

    def parsed_page(path: Path) -> PageLinks:
        """Parse each page once, when a link first needs it."""
        if path not in cache:
            page = PageLinks()
            page.feed(path.read_text())
            cache[path] = page
        return cache[path]

    corrected = 0
    for origin in our_pages(output):
        replacements: dict[str, str] = {}
        for link in parsed_page(origin).links:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc or not parsed.fragment:
                continue
            target = (origin.parent / unquote(parsed.path)).resolve() if parsed.path else origin
            if not target.is_relative_to(output) or not target.is_file() or target.suffix != ".html":
                continue
            ids = parsed_page(target).ids
            fragment = unquote(parsed.fragment)
            parent, separator, suffix = fragment.rpartition(".")
            if (parsed.fragment not in ids and fragment not in ids and separator
                    and suffix in OMITTED_RECURSOR_SUFFIXES and parent in ids):
                replacements[link] = parsed._replace(fragment=quote(parent, safe=".")).geturl()
        if replacements:
            text = origin.read_text()
            for old, new in replacements.items():
                attribute = f'href="{escape(old, quote=True)}"'
                count = text.count(attribute)
                if not count:
                    raise ValueError(f"Reference link format differs in {origin}; inspect the doc-gen4 update")
                text = text.replace(attribute, f'href="{escape(new, quote=True)}"')
                corrected += count
            origin.write_text(text)
    return corrected


def generate_reference(root: Path, executable: Path, build: Path) -> dict[str, int]:
    """Add each public module to the copied core database, write the pages, correct our links.

    Source links contain the placeholder, so the result depends only on the Lean sources, the
    core build and the pinned doc-gen4. Fails when no recursor link needs a correction: then the
    doc-gen4 bug may be fixed, and the correction can go.
    """
    database = build / CORE_DATABASE
    if not database.is_file():
        raise ValueError(f"Core documentation database is missing: {database}; build apiReferenceCore first")

    def run(*arguments: str) -> None:
        """Run doc-gen4 in Lake's environment of our project, so it finds our compiled modules."""
        subprocess.run(["lake", "env", str(executable), *arguments], cwd=root,
                       check=True, timeout=COMMAND_TIMEOUT_SECONDS)

    modules: list[str] = []
    for source in public_sources(root):
        relative = source.relative_to(root)
        module = ".".join(module_source_path(root, source).with_suffix("").parts)
        modules.append(module)
        uri = f"{SOURCE_REPOSITORY}/blob/{SOURCE_REVISION_PLACEHOLDER}/{relative.as_posix()}"
        run("single", "--build", str(build), module, CORE_DATABASE, uri)
    run("fromDb", "--build", str(build), "--manifest", str(build / "manifest.json"), str(database), *modules)
    corrected = correct_recursor_links(build / "doc")
    if not corrected:
        raise ValueError("No recursor link on our pages needed a correction; doc-gen4 may have fixed the bug "
                         "in OMITTED_RECURSOR_SUFFIXES. Remove correct_recursor_links and its tests.")
    report = {"public_modules": len(modules), "corrected_links": corrected}
    (build / "doc/reference-check.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    """Accept Nix's explicit tool, source directory and copied core build directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    arguments = parser.parse_args()
    generate_reference(arguments.root.resolve(), arguments.executable.resolve(), arguments.build.resolve())


if __name__ == "__main__":
    main()
