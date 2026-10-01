"""`prepare` reuses a candidate module unless its source or something it imports changed."""

import pytest

from migration_check.module_keys import contract_keys, module_keys

pytestmark = [pytest.mark.unit]

# Shaped like the Atuin candidate: two modules import only the approved contract.
ORDER = ("NextInterpretation", "AtuinWitness", "HistoryDecodingChecks", "Generated", "AtuinFacts", "Proofs")
IMPORTS = {
    "NextInterpretation": ("Interpretation", "SqlInputs"),
    "AtuinWitness": ("Interpretation",),
    "HistoryDecodingChecks": ("HistoryDecoding",),
    "Generated": ("Requirements", "Interpretation", "SqlInputs", "NextInterpretation"),
    "AtuinFacts": ("NextInterpretation", "Lean"),
    "Proofs": ("Generated", "AtuinFacts", "AtuinWitness", "HistoryDecodingChecks"),
}
CONTRACT = frozenset({"Requirements", "Interpretation", "HistoryDecoding"})
HASHES = {"approved/Requirements.lean": "r", "approved/Interpretation.lean": "i",
          "approved/HistoryDecoding.lean": "h", "generated/SchemaInputs.lean": "s",
          "generated/SqlInputs.lean": "q"}


def keys(hashes: dict[str, str] = HASHES, **sources: bytes) -> dict[str, str]:
    """Keys for the fixture with optional per-module source overrides."""
    contract_key, sql_key = contract_keys(hashes)
    return module_keys(order=ORDER, imports=IMPORTS, contract_modules=CONTRACT, contract_key=contract_key,
                       sql_key=sql_key, runtime=("/lean", "/lib"),
                       sources={name: sources.get(name, name.encode()) for name in ORDER})


def changed(before: dict[str, str], after: dict[str, str]) -> set[str]:
    """Modules whose key differs."""
    return {name for name in before if before[name] != after[name]}


def test_proof_edit_changes_only_proofs() -> None:
    """Nothing imports Proofs, so only it recompiles."""
    assert changed(keys(), keys(Proofs=b"edited")) == {"Proofs"}


def test_sql_edit_skips_modules_without_sql_inputs() -> None:
    """A migration change leaves contract-only modules reusable."""
    after = keys({**HASHES, "generated/SqlInputs.lean": "q2"})
    assert changed(keys(), after) == {"NextInterpretation", "Generated", "AtuinFacts", "Proofs"}


def test_contract_or_schema_edit_invalidates_every_importer() -> None:
    """Approved modules and SchemaInputs change the contract key, reaching all modules here."""
    for name in ("approved/HistoryDecoding.lean", "generated/SchemaInputs.lean"):
        assert changed(keys(), keys({**HASHES, name: "changed"})) == set(ORDER), name


def test_intermediate_edit_propagates_to_importers() -> None:
    """Editing NextInterpretation reaches Generated, AtuinFacts and Proofs, not the witness."""
    assert changed(keys(), keys(NextInterpretation=b"edited")) == {
        "NextInterpretation", "Generated", "AtuinFacts", "Proofs"}


def test_runtime_identity_changes_every_key() -> None:
    """A rebuilt toolchain or library invalidates everything."""
    contract_key, sql_key = contract_keys(HASHES)
    other = module_keys(order=ORDER, imports=IMPORTS, contract_modules=CONTRACT, contract_key=contract_key,
                        sql_key=sql_key, runtime=("/lean2", "/lib"),
                        sources={name: name.encode() for name in ORDER})
    assert changed(keys(), other) == set(ORDER)
