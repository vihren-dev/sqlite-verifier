"""Join compiler-original binder references to parser declarators and direct Verso metadata."""

from collections import Counter
import hashlib
import json
from pathlib import Path
from typing import TypeAlias, cast

Position: TypeAlias = tuple[int, int, int, int]
"""Zero-based line and UTF-16 column bounds, exactly as stored in Lean's reference files."""
DOCUMENTATION_GAPS = ("ordinary", "missing", "unclassified")
"""Each of these states means authored public checked coverage is incomplete."""
COVERAGE_COUNTS = ("authored", "checked", *DOCUMENTATION_GAPS, "excluded")
"""Retain authored coverage and explicit exclusions in each module and the complete import closure."""
CHECKED_DOCUMENTATION_EXCLUSION = "temporary declaration in compiled checked documentation"
"""A discarded Verso code-block declaration has source evidence, but does not export a public API item."""


def mapping(value: object, context: str) -> dict[str, object]:
    """Reject malformed compiler JSON before using it as coverage evidence."""
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ValueError(f"Invalid object in {context}; rebuild the documentation inventory")
    return dict(value)


def sequence(value: object, context: str) -> list[object]:
    """Require the ordered compiler arrays used for source ranges and declarations."""
    if not isinstance(value, list):
        raise ValueError(f"Invalid array in {context}; rebuild the documentation inventory")
    return value


def text(value: object, context: str) -> str:
    """Keep module and declaration identities as exact compiler strings."""
    if not isinstance(value, str):
        raise ValueError(f"Invalid name in {context}; rebuild the documentation inventory")
    return value


def position(value: object, context: str) -> Position:
    """Decode a source selection without rounding or accepting boolean coordinates."""
    coordinates = sequence(value, f"source selection in {context}")[:4]
    if len(coordinates) != 4 or not all(type(item) is int and item >= 0 for item in coordinates):
        raise ValueError(f"Invalid source selection in {context}; rebuild the documentation inventory")
    return cast(Position, tuple(coordinates))


def original_binders(references: dict[str, object], module: str) -> dict[str, Position]:
    """Lean records these constant definitions only for original syntax with isBinder=true."""
    if references.get("module") != module:
        raise ValueError(f"Compiler reference module differs from {module}; rebuild the library")
    result: dict[str, Position] = {}
    for encoded, raw in mapping(references.get("references"), module).items():
        identity = mapping(json.loads(encoded), "reference identity")
        if "c" not in identity:
            continue
        constant = mapping(identity["c"], "constant reference")
        reference = mapping(raw, "reference location")
        if constant.get("m") == module and reference.get("definition") is not None:
            name = text(constant.get("n"), "constant name")
            result[name] = position(reference["definition"], f"{module}: {name}")
    return result


def constant_exclusion_reason(constant: dict[str, object], selection: Position | None) -> str | None:
    """Only compiler-private constants and constants without authored binder evidence escape public coverage."""
    if constant.get("private") is True:
        return "compiler-private declaration"
    if selection is None:
        return "compiler constant has no original-source binder or anonymous-instance declarator"
    return None


def example_exclusion_reason(slot: dict[str, object]) -> str | None:
    """Anonymous parser examples do not export an API constant; named `_example` definitions remain authored."""
    return "anonymous parser example is not an exported declaration" if slot.get("role") == "example" else None


def containing_documentation(selection: Position, checked_ranges: list[Position]) -> Position | None:
    """Lean discards code-block environments; only containment in compiled checked documentation permits exclusion."""
    return next((bounds for bounds in checked_ranges
                 if bounds[:2] <= selection[:2] and selection[2:] <= bounds[2:]), None)


def module_coverage(raw: object) -> dict[str, object]:
    """Require compiler binder names and source grammar roles to agree at exact positions."""
    module = mapping(raw, "module")
    name = text(module.get("module"), "module name")
    source = Path(text(module.get("source"), "module source"))
    reference_path = Path(text(module.get("references"), "compiler references"))
    references = mapping(json.loads(reference_path.read_text()), "compiler references")
    binders = original_binders(references, name)
    checked_ranges = [position(value, f"{name}: checked module documentation") for value in
                      sequence(module.get("checked_module_documentation_ranges"), f"{name}: checked module documentation")]
    declarations = [mapping(value, "source declarator") for value in sequence(module.get("declarators"), name)]
    slots = {position(value["selection"], f"{name}: {value.get('parserKind')}"): value for value in declarations}
    if len(slots) != len(declarations):
        raise ValueError(f"Ambiguous source declarators in {source}; inspect the parser selections")
    constants = [mapping(value, "constant") for value in sequence(module.get("constants"), name)]
    metadata = {text(value.get("name"), "constant name"): value for value in constants}
    authored: list[dict[str, object]] = []
    excluded: list[dict[str, object]] = []
    unknown: list[dict[str, object]] = []
    matched: set[Position] = set()
    for constant_name, constant in sorted(metadata.items()):
        selection = binders.get(constant_name)
        slot = slots.get(selection) if selection is not None else None
        if slot is None and constant.get("instance") is True and constant.get("selection") is not None:
            candidate = position(constant["selection"], f"{name}: {constant_name}")
            if slots.get(candidate, {}).get("anonymousInstance") is True:
                selection, slot = candidate, slots[candidate]
        base = {"name": constant_name, "kind": constant.get("kind"),
                "selection": list(selection) if selection is not None else constant.get("selection"),
                "compiler_range": constant.get("range"),
                "compiler_recursion_helper": constant.get("compiler_recursion_helper") is True,
                "original_source_binder": constant_name in binders,
                "documented": constant.get("documented") is True, "verso": constant.get("verso") is True}
        if base["verso"] is True and slot is not None:
            checked_ranges.extend(position(value, f"{name}: {constant_name} documentation")
                                  for value in sequence(slot.get("documentation"), f"{name}: {constant_name} documentation"))
        exclusion = constant_exclusion_reason(constant, selection)
        if exclusion is not None:
            excluded.append({**base, "reason": exclusion})
            if selection is not None and slot is not None:
                matched.add(selection)
        elif selection is not None and slot is not None:
            matched.add(selection)
            authored.append({**base, "role": slot.get("role"), "parser_kind": slot.get("parserKind")})
        elif selection is not None:
            unknown.append({**base, "reason": "original compiler binder has no recognized source declarator"})
    for constant_name, selection in binders.items():
        if constant_name not in metadata:
            exclusion = example_exclusion_reason(slots.get(selection, {}))
            documentation = containing_documentation(selection, checked_ranges)
            if exclusion is not None:
                excluded.append({"name": constant_name, "selection": list(selection),
                                 "reason": exclusion})
                matched.add(selection)
            elif documentation is not None:
                excluded.append({"name": constant_name, "selection": list(selection),
                                 "checked_documentation_range": list(documentation),
                                 "reason": CHECKED_DOCUMENTATION_EXCLUSION})
            else:
                unknown.append({"name": constant_name, "selection": list(selection),
                                "reason": "original compiler binder is absent from the imported environment"})
    for selected, slot in slots.items():
        if selected not in matched:
            exclusion = example_exclusion_reason(slot)
            if exclusion is not None:
                excluded.append({"selection": list(selected), "parser_kind": slot.get("parserKind"),
                                 "reason": exclusion})
            else:
                unknown.append({"selection": list(selected), "parser_kind": slot.get("parserKind"),
                                "reason": "source declarator has no classified compiler binder"})
    counts = Counter("checked" if item["verso"] else "ordinary" if item["documented"] else "missing"
                     for item in authored)
    return {"module": name, "source": str(source), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "references_sha256": hashlib.sha256(reference_path.read_bytes()).hexdigest(),
            "checked_documentation_ranges": [list(bounds) for bounds in sorted(set(checked_ranges))],
            "authored": authored, "excluded": excluded, "unclassified": unknown,
            "counts": {"authored": len(authored), "checked": counts["checked"],
                       "ordinary": counts["ordinary"], "missing": counts["missing"],
                       "unclassified": len(unknown), "excluded": len(excluded)}}


def coverage_report(metadata: object) -> dict[str, object]:
    """Missing, ordinary and unclassified declarations keep the final gate incomplete."""
    root = mapping(metadata, "inventory input")
    modules = [module_coverage(value) for value in sequence(root.get("modules"), "module inventory")]
    totals = {key: sum(cast(int, mapping(module["counts"], "counts")[key]) for module in modules)
              for key in COVERAGE_COUNTS}
    complete = bool(modules) and all(totals[key] == 0 for key in DOCUMENTATION_GAPS)
    return {"format_version": 1, "entry": root.get("entry"), "lean_version": root.get("lean_version"),
            "complete": complete, "counts": totals, "modules": modules}
