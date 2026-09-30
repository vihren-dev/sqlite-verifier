"""Dependency-aware cache keys for `prepare`'s candidate modules (ADR 0003 P2).

A module's key covers its own source, the runtime identity and the keys of
everything it imports, so an edit invalidates exactly the edited module and its
importers. Approved modules and `SchemaInputs` share one contract key, because every
approved `.olean` is compiled against `SchemaInputs`; `SqlInputs` has its own key
covering both generated inputs. Library imports are covered by the runtime identity.
"""

import hashlib

from .stage_store import digest

CONTRACT_PREFIXES = ("approved/", "generated/SchemaInputs")


def contract_keys(hashes: dict[str, str]) -> tuple[str, str]:
    """(approved-contract key, SqlInputs key) from a compiled contract's input hashes."""
    contract = digest({name: value for name, value in hashes.items() if name.startswith(CONTRACT_PREFIXES)})
    sql = digest({"schema": hashes["generated/SchemaInputs.lean"], "sql": hashes["generated/SqlInputs.lean"]})
    return contract, sql


def module_keys(*, order: tuple[str, ...], sources: dict[str, bytes], imports: dict[str, tuple[str, ...]],
                contract_modules: frozenset[str], contract_key: str, sql_key: str,
                runtime: tuple[str, ...]) -> dict[str, str]:
    """Key every candidate module in topological order from its source and its imports' keys."""
    keys: dict[str, str] = {}
    for name in order:
        dependencies: list[tuple[str, str]] = []
        for dependency in imports.get(name, ()):
            if dependency in keys:
                dependencies.append((dependency, keys[dependency]))
            elif dependency == "SqlInputs":
                dependencies.append((dependency, sql_key))
            elif dependency == "SchemaInputs" or dependency in contract_modules:
                dependencies.append((dependency, contract_key))
        keys[name] = digest({"module": name, "source": hashlib.sha256(sources[name]).hexdigest(),
                             "runtime": list(runtime), "imports": sorted(dependencies)})
    return keys
