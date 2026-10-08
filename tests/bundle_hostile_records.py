"""Handcrafted records reach replay when source compilation or export would omit an attack."""

import json
from pathlib import Path
from typing import cast

from migration_check.structural import Json


class HostileBundle:
    """Extend a real export using the pinned lean4export 3.1.0 name/expression/constant schema."""

    def __init__(self, path: Path) -> None:
        """Read trusted test output, retaining all original lines and declaration identities."""
        lines = path.read_text().splitlines()
        self.header, self.metadata = lines[:2]
        self.records = [cast(dict[str, Json], json.loads(line)) for line in lines[2:]]
        self.names: dict[str, int] = {"": 0}
        indexed: dict[int, str] = {0: ""}
        for record in self.records:
            if "in" in record:
                kind = "str" if "str" in record else "num"
                data = cast(dict[str, Json], record[kind])
                index, previous = int(str(record["in"])), int(str(data["pre"]))
                part = str(data["str"] if kind == "str" else data["i"])
                name = (indexed[previous] + "." if indexed[previous] else "") + part
                indexed[index], self.names[name] = name, index
        self.next_name = max(indexed) + 1
        self.next_expression = max(int(str(record["ie"])) for record in self.records if "ie" in record) + 1

    def name(self, name: str) -> int:
        """Append namespace components only when the real export has not already named them."""
        if name not in self.names:
            previous, _, part = name.rpartition(".")
            parent = self.name(previous)
            index = self.next_name
            self.next_name += 1
            self.names[name] = index
            self.records.append({"in": index, "str": {"pre": parent, "str": part}})
        return self.names[name]

    def expression(self, kind: str, payload: Json) -> int:
        """Add an expression before any new declaration that refers to it."""
        index = self.next_expression
        self.next_expression += 1
        self.records.append({"ie": index, kind: payload})
        return index

    def constant(self, name: str) -> int:
        """Refer to an existing protected constant without exporting its definition."""
        return self.expression("const", {"name": self.name(name), "us": []})

    def proof(self) -> tuple[dict[str, Json], dict[str, Json]]:
        """Select the submitted positive proof by its complete name rather than record position."""
        index = self.names["Proofs.migrationCorrect"]
        for record in self.records:
            value = record.get("thm")
            if isinstance(value, dict) and value.get("name") == index:
                return record, value
        raise AssertionError("Fixture export has no positive theorem record")

    def unsafe_or_partial(self, safety: str) -> None:
        """Keep the honest target/body, changing only the declaration kind and safety flag."""
        record, proof = self.proof()
        record.clear()
        record["def"] = {**proof, "hints": "opaque", "safety": safety}

    def forged_body(self) -> None:
        """Use a well-formed True proof as the body of the genuine migration proposition."""
        record, proof = self.proof()
        self.records.remove(record)
        proof["value"] = self.constant("True.intro")
        self.records.append(record)

    def protected(self, name: str) -> None:
        """Submit a changed protected record that preparation cannot compile against trusted imports."""
        type_index, value_index = self.constant("Nat"), self.expression("natVal", "0")
        self.records.append({"def": {"name": self.name(name), "levelParams": [], "type": type_index,
            "value": value_index, "hints": "opaque", "safety": "safe", "all": [self.name(name)]}})

    def changed_profile(self) -> None:
        """Use the real profile type and other constructor against the frontend's sealed sqlite351 input."""
        type_index = self.constant("SqliteVerifier.ExecutionProfile")
        value_index = self.constant("SqliteVerifier.ExecutionProfile.sqlite346")
        name = self.name("Generated.profile")
        self.records.append({"def": {"name": name, "levelParams": [], "type": type_index,
            "value": value_index, "hints": "opaque", "safety": "safe", "all": [name]}})

    def write(self, path: Path) -> Path:
        """Retain the exact hostile bytes passed to the checker for failure diagnosis."""
        path.write_text("\n".join([self.header, self.metadata, *map(json.dumps, self.records)]) + "\n")
        return path
