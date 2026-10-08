"""Put the checked commit into the source links of a base API reference.

The base build (`tools/api_reference.py`) writes the placeholder `SOURCE-REVISION` into every
source link, so Nix can reuse it for each commit with the same Lean sources. This step copies
the base and replaces the placeholder. It does not change pages, local links or their check.
"""

import argparse
import json
from pathlib import Path
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.api_reference import SOURCE_REPOSITORY, SOURCE_REVISION_PLACEHOLDER, source_revision

REPORT = "reference-check.json"
"""The check report of the base build, which this step completes with the commit."""


def link_sources(base: Path, output: Path, revision: str) -> int:
    """Copy `base` to `output` with the commit in each source link; return the link count.

    Every file that contains the placeholder link prefix gets the commit instead. The result
    must contain no placeholder, and each link to the repository's sources must name the
    commit, so a stale or foreign source link cannot reach the published reference.
    """
    revision = source_revision(revision)
    placeholder = f"{SOURCE_REPOSITORY}/blob/{SOURCE_REVISION_PLACEHOLDER}/".encode()
    checked = f"{SOURCE_REPOSITORY}/blob/{revision}/".encode()
    repository = f"{SOURCE_REPOSITORY}/blob/".encode()
    shutil.copytree(base, output, symlinks=True)
    links = 0
    for path in sorted(output.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        count = data.count(placeholder)
        if count:
            path.chmod(path.stat().st_mode | 0o200)
            data = data.replace(placeholder, checked)
            path.write_bytes(data)
            links += count
        if SOURCE_REVISION_PLACEHOLDER.encode() in data:
            raise ValueError(f"Reference placeholder remains in {path}; inspect the base build")
        if data.count(repository) != data.count(checked):
            raise ValueError(f"Reference source link names another commit in {path}; rebuild the base")
    if not links:
        raise ValueError(f"Reference base has no source links: {base}; rebuild the base")
    report_path = output / REPORT
    report = json.loads(report_path.read_text())
    report["source_revision"] = revision
    report["source_links"] = links
    report_path.chmod(report_path.stat().st_mode | 0o200)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    return links


def main() -> None:
    """Accept the base build, the output directory and the checked commit from Nix."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    arguments = parser.parse_args()
    link_sources(arguments.base, arguments.output, arguments.revision)


if __name__ == "__main__":
    main()
