"""Read frozen corpora and split each record into the subject's input and the recorded truth.

The subject input holds only what exists before the migration runs: the profile and the
SQLite source id that select the SQL dialect, the initial schema SQL and rows, the migration SQL,
the statement parameters and, under a controlled clock, the clock value of each statement. Every later
observation stays with the judge, so the subject cannot copy the answer.
"""

from collections.abc import Iterator
import gzip
import json
from pathlib import Path

from judge.cells import Json, text

CASES_FILE = "cases.jsonl.gz"
"""Corpora v1 to v3 store one record per line in this file; later corpora use shards."""
WITH_OUTPUTS = (3, 4, 5, 6)
"""Native record versions that carry statement parameters and outputs. Version 6 runs on after an
SQL error, so its trace has one event for each statement of the migration."""


def expanded(record: Json, where: str) -> dict[str, Json]:
    """A record with its shared snapshots put back in place.

    Sharded corpora store each distinct table snapshot once, in `snapshots`, and refer to
    it by digest. The lock of the judge covers the corpus bytes, so the digests are not
    checked again here.
    """
    if not isinstance(record, dict):
        raise ValueError(f"{where}: a record is not a JSON object; each line of a corpus file must hold one record")
    if "snapshots" not in record:
        return record
    pool = record["snapshots"]
    observations = [{**observation, **{view: pool[observation[view]["snapshot"]] for view in ("visible", "persisted")}}
                    for observation in [record["initial"], *record["trace"]]]
    plain = {key: value for key, value in record.items() if key not in ("snapshots", "snapshotStorageVersion")}
    return {**plain, "initial": observations[0], "trace": observations[1:]}


def lines(path: Path) -> Iterator[dict[str, Json]]:
    """The records of one gzip-compressed JSON-lines file, expanded, so that single-file and
    sharded corpora give the judge records of one form."""
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for number, line in enumerate(stream, start=1):
            if line.strip():
                yield expanded(json.loads(line), f"{path}:{number}")


def corpus_records(directory: Path) -> Iterator[dict[str, Json]]:
    """The records of one frozen corpus, in stored order: one file, or the shards that
    `manifest.json` lists in order."""
    if (directory / CASES_FILE).is_file():
        yield from lines(directory / CASES_FILE)
        return
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    for shard in manifest["shards"]:
        yield from lines(directory / shard["path"])


def schema_sql(observation: dict[str, Json]) -> str:
    """The recorded `sqlite_schema` SQL, tables first, as the input that recreates the state.

    SQLite lists indexes before tables; the input must declare a table before its index.
    Objects without SQL (automatic indexes) are left out, as SQLite creates them itself.
    """
    rows = observation["schema"]
    if not isinstance(rows, list):
        raise ValueError("recorded schema is not a list")
    ordered = sorted(rows, key=lambda row: text(row[0]) != "table")
    return "\n".join(text(row[3]) + ";" for row in ordered if row[3] != "null")


def initial_rows(observation: dict[str, Json]) -> dict[str, Json]:
    """The recorded rows of each initial table, by table name, as the subject's starting data."""
    tables = observation["tables"]
    if not isinstance(tables, list):
        raise ValueError("recorded tables are not a list")
    return {table["name"]: [{"identity": row["identity"], "values": row["values"]} for row in table["rows"]]
            for table in tables}


def subject_input(record: dict[str, Json]) -> dict[str, Json]:
    """What the subject may see of one record: nothing that was observed after the start."""
    trace = record["trace"]
    if not isinstance(trace, list):
        raise ValueError("recorded trace is not a list")
    initial = record["initial"]["visible"]
    given: dict[str, Json] = {"name": record["name"], "nativeVersion": record.get("nativeVersion"),
                              "profile": record.get("profile"), "sourceId": record.get("sourceId"),
                              "initialSchemaSql": schema_sql(initial),
                              "initialRows": initial_rows(initial), "migrationSql": record["migrationSql"]}
    if record.get("nativeVersion") in WITH_OUTPUTS:
        # Bound parameters are statement inputs. Their list has one entry per executed statement,
        # which tells the subject how far SQLite got (up to version 5, SQLite stops at the first
        # error; version 6 runs every statement); records before version 3 have none.
        given["parameters"] = [event["parameters"] for event in trace]
    if trace and all("clockUnixMilliseconds" in event for event in trace):
        # The recorder's controlled clock is a statement input too: the Unix milliseconds that
        # each executed statement saw. Records without a controlled clock have none.
        given["clockUnixMilliseconds"] = [event["clockUnixMilliseconds"] for event in trace]
    return given


def recorded_steps(record: dict[str, Json]) -> list[dict[str, Json]]:
    """The recorded initial observation and one observation per executed statement."""
    return [record["initial"], *record["trace"]]
