"""Download raw completed-job evidence, including post-action cache and disk observations."""

from datetime import datetime
import io
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request
import zipfile


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Keep the GitHub token off signed log-storage redirect requests."""

    def redirect_request(self, req: object, fp: object, code: int, msg: str,
                         headers: object, newurl: str) -> None:
        """Return the redirect to the caller instead of forwarding authorization."""
        return None


def api(path: str) -> bytes:
    """Fetch GitHub metadata or signed logs with bounded read time."""
    request = urllib.request.Request("https://api.github.com/" + path,
                                    headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                                             "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        target = error.headers["Location"]
        if not target.startswith("https://"):
            raise ValueError("Expected HTTPS log storage") from error
        with urllib.request.urlopen(target, timeout=60) as response:
            return response.read()


def logs_text(raw: bytes) -> str:
    """Read returned text or ZIP members in memory without extracting untrusted paths."""
    if zipfile.is_zipfile(io.BytesIO(raw)):
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            return "\n".join(archive.read(name).decode(errors="replace") for name in archive.namelist())
    return raw.decode(errors="replace")


def duration(row: dict) -> float:
    """Use completed runner timestamps so checkout and cache post hooks remain included."""
    return (datetime.fromisoformat(row["completed_at"].replace("Z", "+00:00")) -
            datetime.fromisoformat(row["started_at"].replace("Z", "+00:00"))).total_seconds()


def observations(job: dict, text: str) -> dict:
    """Expose measured values and explicitly leave unavailable transfer sizes empty."""
    markers = re.findall(r"ADR1_DISK_METRICS=(\{[^\n]+\})", text)
    return {"job_id": job["id"], "conclusion": job["conclusion"],
            "total_seconds": duration(job),
            "cache_steps": [{"name": step["name"], "seconds": duration(step)}
                            for step in job["steps"] if "Restore experiment store" in step["name"]
                            and step.get("completed_at") and step.get("started_at")],
            "reported_cache_bytes": [int(size) for size in re.findall(r"Cache Size:.*?\((\d+) B\)", text)],
            "disk": json.loads(markers[-1]) if markers else None}


def collect(evidence: Path, output: Path) -> list[dict]:
    """Preserve full job metadata/logs and join each sample to its own completed runner."""
    base = f"repos/{os.environ['GITHUB_REPOSITORY']}/actions"
    jobs: list[dict] = []
    page = 1
    while True:
        response = json.loads(api(f"{base}/runs/{os.environ['GITHUB_RUN_ID']}/jobs?per_page=100&page={page}"))
        jobs.extend(response["jobs"])
        if len(response["jobs"]) < 100:
            break
        page += 1
    (output / "jobs.json").write_text(json.dumps(jobs, indent=2) + "\n")
    samples = []
    for path in sorted(evidence.rglob("sample.json")):
        sample = json.loads(path.read_text())
        matches = [job for job in jobs if job["name"].endswith(sample["job_name"])]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one job for {sample['job_name']}")
        job = matches[0]
        raw = api(f"{base}/jobs/{job['id']}/logs")
        (output / f"job-{job['id']}.log").write_bytes(raw)
        sample.update(observations(job, logs_text(raw)))
        artifact = path.parent.parent
        sample["case_reports"] = [json.loads(report.read_text())
                                  for report in sorted(artifact.glob("work/build/test-results/*/*.json"))]
        sample["cached_unit_reports"] = [json.loads(report.read_text())
                                          for report in artifact.glob("work/build/cached-unit/source/unit.json")]
        source_catalogue = artifact / "work/build/source-catalogue.json"
        sample["source_ids"] = ([row["node_id"] for row in json.loads(source_catalogue.read_text())]
                                if source_catalogue.exists() else [])
        manifest = artifact / "work/build/cached-unit/unit-cases.json"
        sample["unit_ids"] = json.loads(manifest.read_text()) if manifest.exists() else []
        inventory = json.loads((path.parent / "legacy-to-node-mapping.json").read_text())
        sample["installed_ids"] = [row["node_id"] for row in inventory["cases"]
                                   if "installed" in row["runtimes"]]
        coverage = artifact / "work/build/coverage.json"
        sample["source_run_id"] = json.loads(coverage.read_text()).get("run_id") if coverage.exists() else None
        sample["environment"] = [json.loads(report.read_text())
                                  for report in artifact.glob("work/build/ci-environment.json")]
        samples.append(sample)
    return samples
